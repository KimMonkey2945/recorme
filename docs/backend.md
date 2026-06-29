# record 백엔드 구조 (Spring Boot + MyBatis)

> Java 21 / Spring Boot 3.x / MyBatis / PostgreSQL. 패키지 베이스 `com.recordapp`.

## 1. 패키지 트리 (도메인 기반)

```
com.recordapp
├─ RecordApplication.java
├─ global
│  ├─ config/        (SecurityConfig, WebConfig, MyBatisConfig, LlmConfig, AsyncConfig)
│  ├─ common/        (ApiResponse, PageResponse, CursorRequest)
│  ├─ exception/     (BusinessException, ErrorCode, GlobalExceptionHandler)
│  ├─ security/      (SupabaseJwtVerifier, SupabaseJwtFilter, SecurityConfig, SecurityUser)
│  └─ util/
├─ domain
│  ├─ auth
│  │  └─ service/    (UserProvisioningService — Supabase JWT의 sub/email로 users 자동 가입·매핑)
│  │     (소셜 검증·JWT 발급·refresh 회전은 Supabase Auth가 전담 → controller/social/token 서비스 없음)
│  ├─ user
│  │  └─ controller/ (UserController — GET/PUT /users/me, POST /users/me/avatar)
│  │     service/ (UserService) mapper/ (UserMapper) dto/ (UserProfileResponse, UpdateProfileRequest) vo/
│  ├─ diary
│  │  ├─ controller/ (DiaryController)
│  │  ├─ service/    (DiaryService)
│  │  ├─ mapper/     (DiaryMapper)
│  │  ├─ dto/        (DiaryCreateRequest, DiaryUpdateRequest, DiaryResponse, DiaryFeedItem)
│  │  └─ vo/         (Diary)
│  ├─ emotion
│  │  ├─ service/    (EmotionAnalysisService, EmotionAnalyzer(if))
│  │  ├─ mapper/     (EmotionAnalysisMapper)
│  │  └─ dto/        (EmotionResult)
│  ├─ theme
│  │  └─ service/ mapper/ dto/
│  ├─ music
│  │  ├─ service/    (MusicService, MusicSource(if))
│  │  ├─ mapper/     (TrackMapper)
│  │  └─ dto/
│  └─ social         (friendship + reaction)
│     └─ controller/ service/ mapper/ dto/
└─ infra
   ├─ llm/           (LlmClient(if), ClaudeLlmClient, OpenAiLlmClient, prompt/)
   ├─ music/         (LocalFileMusicSource, SpotifyMusicSource ... 추후)
   └─ storage/       (StorageService(if), LocalDiskStorageService, StorageProperties — S3StorageService 추후)
```

> **파일 업로드/정적 서빙**: 프로필 이미지는 `POST /users/me/avatar`(multipart)로 받아 `StorageService`(인프라 격리, 로컬 디스크 → S3 교체 가능)가 매직바이트 검증 후 `{root}/avatars/yyyy/MM/{uuid}.{ext}`에 저장하고 상대 경로(`/files/...`)를 반환한다. DB(`users.profile_image_url`)에는 경로만 저장(BYTEA 미사용). 정적 서빙은 `global/config/WebMvcConfig`가 `/files/**`를 저장 루트로 매핑하고, `SecurityConfig`에서 `GET /files/**`를 permitAll(공개)로 연다. 멀티파트 한도(5MB)는 `application.yml`(`spring.servlet.multipart.*`), 초과 시 `GlobalExceptionHandler`가 `FILE_TOO_LARGE`(413)로 변환한다.

- MyBatis XML: `backend/src/main/resources/mapper/*.xml` (mapper 인터페이스와 1:1).
- **도메인 기반 채택 근거**: 기능 경계가 명확(auth/diary/emotion/social)하고 신규 기능을 패키지 단위로 응집·추가/삭제할 수 있다. 레이어 기반은 도메인이 적을 때만 유리하나 본 앱은 도메인이 다수.

## 2. 계층 구조

```
Controller(검증/직렬화) → Service(@Transactional/비즈니스) → Mapper(MyBatis/SQL) → DB
```

- **VO**: DB 행 매핑(`vo` 패키지, 가변 최소화).
- **DTO**: Request/Response 분리. 외부에 VO/Entity 직접 노출 금지.
- **트랜잭션 경계**: Service 메서드. **LLM 외부 호출은 트랜잭션 밖**(비동기 분리).

## 3. API 응답 표준 포맷

```java
// 성공: { "success": true, "data": {...}, "error": null }
// 실패: { "success": false, "data": null, "error": { "code": "...", "message": "..." } }
public record ApiResponse<T>(boolean success, T data, ApiError error) {
    public static <T> ApiResponse<T> ok(T data) {
        return new ApiResponse<>(true, data, null);
    }
    public static ApiResponse<Void> fail(ErrorCode code) {
        return new ApiResponse<>(false, null, new ApiError(code.name(), code.getMessage()));
    }
    public record ApiError(String code, String message) {}
}
```

- 예외 처리: `BusinessException(ErrorCode)` → `@RestControllerAdvice`(`GlobalExceptionHandler`)에서 HTTP 상태 + 표준 포맷으로 변환. 예상 못한 예외는 500 + `INTERNAL_ERROR`(상세 메시지 마스킹).

## 4. MyBatis 매퍼 예시 (동적 SQL — 피드 조회)

```java
// DiaryMapper.java
@Mapper
public interface DiaryMapper {
    long upsert(Diary diary);                         // 하루 1기록 저장(날짜 키 INSERT … ON CONFLICT DO UPDATE)
    int update(Diary diary);                          // id 기반 명시적 수정(PUT /diaries/{id})
    Optional<DiaryResponse> findDetailById(@Param("id") long id,
                                           @Param("viewerId") long viewerId);
    List<DiaryFeedItem> findFeed(@Param("viewerId") long viewerId,
                                 @Param("cursor") Long cursor,
                                 @Param("size") int size);
    int updateAnalysisResult(@Param("diaryId") long diaryId,
                             @Param("status") String status,
                             @Param("themeId") Long themeId,
                             @Param("trackId") Long trackId);
}
```

```xml
<!-- mapper/DiaryMapper.xml -->
<mapper namespace="com.recordapp.domain.diary.mapper.DiaryMapper">

  <!-- 하루 1기록 upsert: (user_id, written_date) 부분 유니크(deleted_at IS NULL)를 충돌 키로 사용.
       날짜 미존재 시 INSERT, 존재 시 UPDATE → 클라는 id 없이 날짜+내용만으로 저장 가능, 409 경쟁 조건 없음.
       RETURNING id 를 generated key 로 받아 신규/갱신 모두 동일하게 id 확보.
       confirm 분기: '등록'(confirm=false)은 DRAFT(미분석), '오늘을 기억하기'(confirm=true)는 PENDING(확정·분석대기).
       불변성 가드: DRAFT 인 행만 UPDATE 허용(WHERE analysis_status='DRAFT'). 이미 확정된 행은
       WHERE 조건 불일치로 업데이트 0건 → 서비스가 DIARY_ALREADY_CONFIRMED(409)로 변환. -->
  <insert id="upsert" parameterType="com.recordapp.domain.diary.vo.Diary"
          useGeneratedKeys="true" keyProperty="id" keyColumn="id">
    INSERT INTO diaries (user_id, content, written_date, visibility, analysis_status)
    VALUES (#{userId}, #{content}, #{writtenDate}, #{visibility},
            <choose><when test="confirm">'PENDING'</when><otherwise>'DRAFT'</otherwise></choose>)
    ON CONFLICT (user_id, written_date) WHERE deleted_at IS NULL
    DO UPDATE SET
      content         = EXCLUDED.content,
      visibility      = EXCLUDED.visibility,
      -- 확정 시 PENDING 으로 승격(분석 1회), 미확정 재저장은 DRAFT 유지
      analysis_status = <choose><when test="confirm">'PENDING'</when><otherwise>'DRAFT'</otherwise></choose>,
      updated_at      = now()
    -- DRAFT(미확정) 행만 갱신 허용 → 확정된 기록은 0건 갱신(서비스가 409로 변환)
    WHERE diaries.analysis_status = 'DRAFT'
    RETURNING id
  </insert>

  <!-- 친구(FRIENDS)·공개(PUBLIC)·본인 글을 커서 페이징으로 조회 -->
  <select id="findFeed" resultType="com.recordapp.domain.diary.dto.DiaryFeedItem">
    SELECT d.id, d.user_id, u.nickname, d.content, d.written_date,
           d.visibility, ea.primary_emotion, d.theme_id, d.track_id, d.created_at
    FROM diaries d
    JOIN users u ON u.id = d.user_id
    LEFT JOIN emotion_analyses ea ON ea.diary_id = d.id
    WHERE d.deleted_at IS NULL
      AND (
        d.user_id = #{viewerId}
        OR d.visibility = 'PUBLIC'
        OR (d.visibility = 'FRIENDS' AND d.user_id IN (
              SELECT CASE WHEN requester_id = #{viewerId} THEN addressee_id
                          ELSE requester_id END
              FROM friendships
              WHERE status = 'ACCEPTED'
                AND (#{viewerId} IN (requester_id, addressee_id))
        ))
      )
    <if test="cursor != null">
      AND d.id &lt; #{cursor}
    </if>
    ORDER BY d.id DESC
    LIMIT #{size}
  </select>

  <update id="updateAnalysisResult">
    UPDATE diaries
    SET analysis_status = #{status},
        theme_id = #{themeId},
        track_id = #{trackId},
        updated_at = now()
    WHERE id = #{diaryId}
  </update>
</mapper>
```

- **동적 SQL 활용 지점**: 피드 가시성 필터, 커서 페이징(`<if>`), 검색/정렬 옵션, 부분 수정(`<set>`).
- **커서 페이징** 권장(무한 스크롤 피드, OFFSET 비효율 회피).

## 5. 인증 흐름 (Supabase Auth + 백엔드 JWT 검증)

```
[앱] Supabase SDK 로그인 (소셜 또는 이메일)
  - 구글: google_sign_in → idToken → supabase.signInWithIdToken(google)
  - 카카오: supabase.signInWithOAuth(kakao) 웹 OAuth(딥링크 콜백)
  - 이메일: supabase.signUp(email,password,data:{nickname}) / signInWithPassword (확인 메일 필수)
  → Supabase 세션 발급(access JWT ~1h + refresh). SDK가 저장·자동 갱신.
[앱→백엔드] Authorization: Bearer <Supabase access token>
[백엔드] SupabaseJwtFilter
  → 프로젝트 JWKS(ES256 비대칭 공개키)로 서명/만료/aud 검증
  → sub(Supabase user uuid)·email 클레임 추출
  → UserProvisioningService: users.supabase_uid 조회, 없으면 자동 가입(JIT)
  → SecurityContext(SecurityUser{userId, supabaseUuid}) 세팅
[로그아웃] 앱에서 supabase signOut (백엔드 상태 없음)
```

- **검증·세션 관리는 Supabase가 전담**: 이메일/비밀번호 인증, 카카오·구글 토큰 검증, JWT 발급/갱신, refresh 회전을 모두 Supabase Auth가 처리한다. 백엔드는 **Supabase가 서명한 access token을 검증만** 한다(자체 발급 없음). **이메일·소셜 모두 동일 형식의 토큰이라 `SupabaseJwtFilter`/`UserProvisioningService`는 provider를 참조하지 않고 같은 경로로 동작**한다(이메일 가입을 위한 추가 분기 없음). **애플은 추후 Supabase Apple provider로 확장**.
- **JIT 프로비저닝**: 백엔드는 `social_accounts`/`refresh_tokens` 테이블을 두지 않는다. `users.supabase_uid`(UNIQUE)로 Supabase 사용자를 매핑하고, 최초 인증 요청 시 JWT 클레임(email)·`user_metadata`(닉네임·프로필)로 `users` 행을 생성한다.
- **검증 방식**: 프로젝트 **JWKS(ES256 비대칭)**. Supabase가 JWT Signing Keys(ES256)로 서명하므로, 백엔드는 `{supabase.url}/auth/v1/.well-known/jwks.json`의 공개키로 검증한다(`NimbusJwtDecoder` + audience `authenticated`). 대칭 secret을 보관하지 않으므로 키 회전에 자동 대응하고 유출 위험이 없다. (참고: legacy HS256 secret 방식은 이 프로젝트에 미적용.)

## 6. LLM 연동 추상화 (감정 분석)

```java
// 추상화: 감정 분석기 — 구현 교체/폴백 용이
public interface EmotionAnalyzer {
    EmotionResult analyze(String diaryContent);
}

// 저수준 LLM 호출 추상화 (provider 교체)
public interface LlmClient {
    LlmResponse complete(LlmRequest request);   // 타임아웃/재시도 내장
}
// 구현: ClaudeLlmClient, OpenAiLlmClient (config의 record.llm.provider 로 선택)
```

- **설정**: `application.yml`의 `record.llm.*`(provider, model, api-key=환경변수, timeout-ms, max-retries). **API 키는 환경변수/시크릿으로 주입(코드·git 금지)**.
- **프롬프트**: "감정 분류 + 점수 분포 + 한줄 요약"을 **구조화 JSON 출력**으로 강제(파싱 안정성·토큰 절감).
- **비용 절감**: 입력 길이 상한·요약, 모델 티어 선택, 동일/유사 입력 단기 캐시(옵션).
- **타임아웃/재시도**: 클라이언트 레벨 타임아웃 + 제한적 재시도. (Resilience4j 서킷브레이커는 트래픽 증가 시 도입 — 초기엔 과함.)
- **폴백**: 실패 시 `primary_emotion=NEUTRAL`, 기본 테마/음악 적용, `analysis_status=FAILED` 기록 → 추후 재분석 배치 가능.

## 7. 감정 분석 동기 vs 비동기 (트레이드오프)

| 방식 | 장점 | 단점 |
|---|---|---|
| 동기(저장 시 LLM 대기) | 구현 단순, 결과 즉시 | 저장 2~5s 지연, LLM 장애 시 저장 실패, 타임아웃 UX 악화 |
| **비동기(권장)** | 저장 즉시 응답, LLM 장애 격리, 재시도 용이 | 상태(PENDING) 관리·클라 폴링 필요 |

**권장: 비동기 경량.** '등록'(confirm=false)은 `DRAFT`로 저장만 하고 **LLM을 호출하지 않는다**(수정 가능). '오늘을 기억하기'(confirm=true)로 **확정**하면 동기로 `PENDING` 즉시 반환 → `@Async`(전용 스레드풀) 또는 `ApplicationEvent` 리스너가 LLM 호출·테마/음악 매핑·`DONE` 갱신. 클라는 상세 재조회 또는 폴링. 외부 큐(SQS/Kafka)는 초기 불필요(트래픽 증가 시 도입). 분석은 트랜잭션 밖에서 수행하고 결과만 별도 트랜잭션으로 커밋.

- **확정 시 1회 분석**: 감정 분석은 **확정 시점(DRAFT→PENDING) 단 1회**만 수행한다. DRAFT 기록은 미분석 상태로 자유롭게 수정할 수 있지만, **확정된 기록은 수정 불가**(재upsert·`PUT` 모두 `DIARY_ALREADY_CONFIRMED`(409)). 따라서 "수정마다 재분석"하던 정책은 폐기됐고, 매 수정 LLM 호출로 인한 과부하가 제거된다. 확정 기록을 다시 쓰려면 삭제(소프트 삭제) 후 같은 날짜에 새로 작성한다.
