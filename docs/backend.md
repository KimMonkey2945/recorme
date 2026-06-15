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
│  ├─ security/      (JwtProvider, JwtAuthenticationFilter, JwtAuthentication, SecurityUser)
│  └─ util/
├─ domain
│  ├─ auth
│  │  ├─ controller/ (AuthController)
│  │  ├─ service/    (AuthService, TokenService)
│  │  ├─ social/     (SocialVerifier(if), KakaoVerifier, GoogleVerifier, AppleVerifier)
│  │  └─ dto/        (SocialLoginRequest, TokenResponse, RefreshRequest)
│  ├─ user
│  │  └─ controller/ service/ mapper/ dto/ vo/
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
   └─ music/         (LocalFileMusicSource, SpotifyMusicSource ... 추후)
```

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
    long insert(Diary diary);
    int update(Diary diary);                          // 하루 1기록 수정
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

  <insert id="insert" parameterType="com.recordapp.domain.diary.vo.Diary"
          useGeneratedKeys="true" keyProperty="id">
    INSERT INTO diaries (user_id, content, written_date, visibility, analysis_status)
    VALUES (#{userId}, #{content}, #{writtenDate}, #{visibility}, 'PENDING')
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

## 5. JWT 인증 흐름

```
[앱] 소셜 SDK 로그인 → idToken/accessToken 획득
  → POST /api/v1/auth/login { provider, token }
[백엔드] SocialVerifier.verify(provider, token)
  → provider_user_id/email/nickname 추출
  → social_accounts 조회: 없으면 users + social_accounts 생성(가입)
  → access(JWT, ~30m) + refresh(랜덤, ~14d, 해시 저장) 발급
  → { accessToken, refreshToken, user } 반환
[이후] Authorization: Bearer <access>
  → JwtAuthenticationFilter 검증 → SecurityContext 세팅
[갱신] POST /api/v1/auth/refresh { refreshToken }
  → 해시 매칭·만료/폐기 확인 → 회전(rotation): 기존 revoke, 신규 발급
[로그아웃] refresh revoke
```

- **소셜 검증**: 카카오(액세스 토큰으로 사용자 API 호출), 구글/애플(idToken JWKS 서명 검증). `SocialVerifier` 인터페이스 + provider별 구현, `Map<provider, verifier>` 라우팅.
- refresh는 평문 미저장(SHA-256 해시), 회전으로 탈취 대응.

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

**권장: 비동기 경량.** 저장/수정은 동기로 `PENDING` 즉시 반환 → `@Async`(전용 스레드풀) 또는 `ApplicationEvent` 리스너가 LLM 호출·테마/음악 매핑·`DONE` 갱신. 클라는 상세 재조회 또는 폴링. 외부 큐(SQS/Kafka)는 초기 불필요(트래픽 증가 시 도입). 분석은 트랜잭션 밖에서 수행하고 결과만 별도 트랜잭션으로 커밋.

- **수정 시 재분석**: 일기 내용이 바뀌면 `analysis_status`를 다시 `PENDING`으로 두고 동일 비동기 경로를 재실행.
