# record 백엔드 구조 (Spring Boot + MyBatis)

> Java 21 / Spring Boot 3.x / MyBatis / PostgreSQL. 패키지 베이스 `com.recordapp`.

## 1. 패키지 트리 (도메인 기반)

```
com.recordapp
├─ RecordApplication.java
├─ global
│  ├─ config/        (SecurityConfig, WebConfig, MyBatisConfig, LlmConfig,
│  │                  AsyncConfig — emotionAnalysisExecutor·pushExecutor
│  │                  (+ characterExecutor는 보상 엔진과 함께 Task 028에서 추가 예정))
│  ├─ common/        (ApiResponse, PageResponse, CursorRequest)
│  ├─ exception/     (BusinessException, ErrorCode, GlobalExceptionHandler)
│  ├─ event/         ⏳ Task 028 예정 (DiaryConfirmedEvent, ResolutionSucceededEvent) — 아직 없음
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
│  ├─ character      ★ Phase 7 — 캐릭터·옷장·미션 (조회·선택·착용 구현 / 보상은 Task 028 예정)
│  │  ├─ CharacterConstants.java  (EQUIPMENT_MAX_ITEMS=12 — EXP_PER_LEVEL은 경험치/레벨 폐기(V18)로 제거)
│  │  ├─ controller/ (CharacterController, WardrobeController, MissionController)
│  │  │                  ⏳ CharacterRewardController — Task 028
│  │  ├─ service/    (CharacterService, WardrobeService, MissionService, CatalogCache)
│  │  │                  ⏳ CharacterRewardService·CharacterEventListener·
│  │  │                     CharacterRewardBackfillPoller·MissionEvaluator·RetrospectService — Task 028/032
│  │  ├─ mapper/     (CharacterCatalogMapper, UserCharacterMapper, MissionMapper)
│  │  │                  ⏳ CharacterEventMapper — Task 028
│  │  ├─ dto/        (CharacterResponse·CharacterListResponse·MyCharacterResponse·SelectedCharacterResponse,
│  │  │               ItemGroupResponse·ItemGroupListResponse·EquippedItemResponse,
│  │  │               MissionResponse·MissionListResponse·MissionLockResponse,
│  │  │               SelectCharacterRequest·UpdateEquipmentRequest·EquipmentItemRequest,
│  │  │               *Row(매퍼 결과) + ResolvedVariant·EquipmentInsertCommand)
│  │  └─ vo/         (ItemSlot, AcquireType, MissionRuleType — DB CHECK 집합과 1:1인 enum)
│  ├─ emotion        LLM 자동 분석 **활성**(현행 유지) — §6·§7 참조
│  │  ├─ service/    (EmotionAnalysisService, EmotionAnalyzer(if), EmotionAnalysisPoller)
│  │  ├─ mapper/     (EmotionAnalysisMapper)
│  │  └─ dto/        (EmotionResult)
│  │  ✅ 수동 감정 입력 전환(플래그로 LLM off)은 Task 024 — **적용됨**(기본 off: 확정 시 즉시 DONE + 사용자 감정 저장).
│  ├─ theme
│  │  └─ service/ mapper/ dto/
│  ├─ music
│  │  ├─ service/    (MusicService, MusicSource(if))
│  │  ├─ mapper/     (TrackMapper)
│  │  └─ dto/
│  ├─ social         (friendship + reaction) — Phase 6 구현본
│  │     └─ controller(FriendController·ReactionController)/ service(FriendService·ReactionService)/
│  │        mapper(FriendshipMapper·ReactionMapper)/ dto/ (+ FriendCodeGenerator)
│  └─ feed            (FeedController·FeedService) — 조회 대상은 diaries라 DiaryMapper 재사용
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
- **트랜잭션 경계**: Service 메서드. **외부 호출(LLM·FCM)·부작용(캐릭터 보상)은 트랜잭션 밖**(커밋 후 비동기 분리).

### 2-1. ApplicationEvent 훅 패턴 (기록·작심삼일 → 캐릭터 보상) — ⏳ 설계, 미구현(Task 028)

> **이 절은 아직 코드가 없다.** `global/event/`·`CharacterEventListener`·`characterExecutor`는 **보상 엔진(Task 028)에서 함께 추가**된다. 현재 `DiaryService`·`ResolutionService`는 이벤트를 발행하지 않으며, 캐릭터 도메인은 조회·선택·착용만 한다(§8).

캐릭터 보상은 **기록 확정**과 **작심삼일 완주**를 트리거로 삼는다. 이때 `DiaryService`가 `CharacterRewardService`를 직접 부르면 diary 도메인이 character를 알게 되고, 보상 실패가 기록 저장을 롤백시킨다. → **이벤트로 뒤집는다.**

**발행** (`global/event/`) — 기존 코드에는 `publishEvent` **한 줄씩만** 추가된다.

| 이벤트 | 발행처 | 시점 |
|---|---|---|
| `DiaryConfirmedEvent(userId, diaryId, writtenDate)` | `DiaryService.upsert` | 확정(`DONE` 전이) 시 |
| `ResolutionSucceededEvent(userId, resolutionId, streakSeq)` | `ResolutionService.completeToday` | `markResolutionSuccessIfAllDone(id) == 1` 블록(기존 push 훅 옆) |

**수신** — `CharacterEventListener`

```java
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
@Async("characterExecutor")
public void on(DiaryConfirmedEvent e) {
    rewardService.onDiaryConfirmed(e.userId(), e.diaryId(), e.writtenDate());
}
```

**트레이드오프**

| 방식 | 장점 | 단점 |
|---|---|---|
| 직접 주입(`DiaryService` → `CharacterRewardService`) | 구현 단순, 호출 흐름이 코드로 바로 보임 | **도메인 결합**(diary가 character를 앎), **보상 실패가 기록 저장을 롤백**, 확정 응답이 보상 처리만큼 느려짐 |
| **ApplicationEvent(채택)** | **단방향**(diary/resolution은 character를 모름), 장애 격리(보상이 터져도 기록은 커밋됨), 확정 응답 즉시 반환, 수신자 추가가 발행처 무수정 | **커밋 직후 크래시 시 이벤트 유실**, 호출 추적이 코드상 끊겨 디버깅 난도↑ |

→ **이벤트 채택 + 백스톱 폴러로 유실 보정.** `CharacterRewardBackfillPoller`가 주기적으로 "확정됐으나 `character_events` 게이트가 없는 기록/완주"를 찾아 재처리한다(멱등 게이트 덕분에 중복 적립 없음). 이는 `EmotionAnalysisPoller`(PENDING 백스톱)와 **동일한 철학** — "비동기 후처리는 유실될 수 있으니, 상태를 보고 뒤늦게 메꾸는 폴러를 항상 둔다".

기존 `TransactionSynchronization.afterCommit` **수동 훅**(작심삼일 FCM 발송)과 공존한다. 둘 다 "커밋 확정 후에만 부작용 실행"이라는 같은 원칙이며, 스프링 표준 어노테이션(`@TransactionalEventListener`)이 이를 선언적으로 표현한 것뿐이다.

`AsyncConfig`에는 전용 풀 **`characterExecutor`**(core 2 / max 4 / queue 200 / `CallerRunsPolicy`)를 추가한다 — 기존 `emotionAnalysisExecutor`와 분리해, LLM 분석이 되살아나도 보상 처리가 굶지 않게 한다.

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

  <!-- ⚠️ 정정(Phase 6 구현): 아래 예시는 존재하지 않는 emotion_analyses 테이블·theme_id/track_id 를
       참조하는 옛 설계다. 실제 스키마는 감정 산출물이 diaries 인라인 컬럼(primary_emotion·mood_emoji·
       ai_title·background_color·accent_color)이고 본문은 content(Delta)+content_text 다. 실제 findFeed 는
       diaries+users 인라인 기준으로 재작성했고(전문 미포함·감정 카드 요약), 정렬/커서는 id DESC,
       공감수는 diaries.reaction_count 캐시·reacted_by_me 는 EXISTS(diary_reactions), 가시성은
       본인 OR PUBLIC OR (FRIENDS AND 수락친구) AND 비차단 이다. 가시성 절은 공용 SQL fragment
       (acceptedFriendIds·notBlockedByPair)로 findViewableById·ReactionMapper.isViewable 과 공유한다. -->
  <!-- 친구(FRIENDS)·공개(PUBLIC)·본인 글을 커서 페이징으로 조회 (옛 예시 — 위 정정 참조) -->
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

### 4-1. 멱등 게이트 패턴 (캐릭터 보상 — 최대 리스크 지점) — ⏳ 설계, 미구현(Task 028)

> **테이블은 있고 코드는 없다.** `character_events`·`user_wallets`는 V17로 이미 존재하지만, 아래 게이트·적립·구매 SQL과 `CharacterEventMapper`는 **Task 028에서 작성**한다. `COIN_INSUFFICIENT` ErrorCode도 그때 추가된다(현재 캐릭터 ErrorCode는 §8의 4종뿐). 현재 `character_events`를 읽는 곳은 홈 배지용 `countUnackedRewards`(미확인 보상 수) 하나뿐이다.

이벤트는 재전달될 수 있고 백스톱 폴러도 같은 건을 다시 집는다. 따라서 **모든 보상 부작용은 단 하나의 관문을 통과**한다.

```xml
<!-- CharacterEventMapper.xml — 멱등 관문. 성공(1행)만이 적립·해금·미션 지급의 유일한 진입 조건 -->
<insert id="insertGate" useGeneratedKeys="true" keyProperty="id" keyColumn="id">
  INSERT INTO character_events (user_id, event_key, event_type, diary_id)
  VALUES (#{userId}, #{eventKey}, #{eventType}, #{diaryId})
  ON CONFLICT (user_id, event_key) DO NOTHING     <!-- 이미 처리된 이벤트 → 0행 -->
  RETURNING id
</insert>
```

```java
int gate = eventMapper.insertGate(userId, "DIARY_CONFIRM:" + diaryId, ...);
if (gate == 0) return;                 // 재전달/폴러 중복 → 조용히 no-op (예외 아님)
int balance = eventMapper.addCoins(userId, COIN_PER_DIARY);
UserProgressRow p = eventMapper.bumpDiaryProgress(userId, date);  // UPSERT + RETURNING
List<Mission> achieved = missionService.evaluate(userId, p);      // 미션도 event_key='MISSION:{code}' 게이트 통과
eventMapper.updatePayload(gate, payload(line, achieved, balance)); // 앱 리액션의 단일 소스
```

- `event_key`는 **의미 있는 자연키**(`DIARY_CONFIRM:{diaryId}`, `RESOLUTION_SUCCESS:{resolutionId}`, `MISSION:{code}`)로 만든다. UUID 같은 랜덤 키는 재시도 시 다른 값이 되어 멱등을 깬다.
- `character_events` 한 테이블이 ① 멱등 관문 ② 코인 원장 ③ 리액션 페이로드 ④ 미확인 보상 알림함을 겸한다.

**코인 소비(구매)는 조건부 UPDATE로 경합을 흡수한다.**

```xml
<update id="spendCoins">
  UPDATE user_wallets SET balance = balance - #{price}
  WHERE user_id = #{userId} AND balance >= #{price}   <!-- 0행 = 잔액 부족 -->
</update>
```

→ 영향 행이 0이면 `COIN_INSUFFICIENT`(409)로 변환한다. `SELECT` 후 검사하는 read-then-write는 동시 구매에서 음수 잔액을 만든다. `balance CHECK (balance >= 0)`은 최종 방어선일 뿐, **1차 방어는 이 `WHERE balance >= ?`**다.

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

## 6. LLM 연동 추상화 (감정 분석) — ⏸ 기본 비활성(Task 024, 플래그로 복구)

> **현재 상태: LLM 자동 감정 분석은 플래그(`record.analysis.enabled`, 기본 `false`)로 꺼져 있다.** 기본 경로에서 확정(`DRAFT`→`DONE`)은 즉시 전이되고 감정은 **사용자 직접 입력**(프리셋 6종 = `emotion_types` FK `primary_emotion`, 또는 자유 텍스트 `diaries.emotion_label` ≤20자, 상호 배타)으로 저장된다. 동시 지정은 400 `EMOTION_CONFLICT`.
>
> ✅ **Task 024 적용됨.** `EmotionAnalysisService`·`LlmEmotionAnalyzer`·`EmotionAnalysisPoller`·`infra/llm/LlmConfig`의 `LlmClient` 빈은 **삭제하지 않고** `@ConditionalOnProperty(name="record.analysis.enabled", havingValue="true")`로 게이팅했다 — `ANALYSIS_ENABLED=true` 한 줄이면 확정 시 `PENDING`→멀티모달 LLM 분석→`DONE`(§7) 경로가 무손상 복구된다(빈이 다시 등록됨). `DiaryService`는 빈 부재를 `ObjectProvider`로 흡수한다.
> - 전환 후: flag off면 확정 시 `analysis_status`가 **즉시 `DONE`**(PENDING 대기 없음) + 사용자 감정 저장, AI 산출 필드(`ai_title`·`background_color`·`accent_color` 등)는 NULL → 캐릭터 리액션 지연 0.
> - 결정 번복의 배경 → [`architecture.md`](./architecture.md) §3.
>
> **아래 내용은 (Task 024 전인) 현행 구현 그대로다.**

```java
// 추상화: 감정 분석기 — 구현 교체/폴백 용이 (멀티모달: 본문 + 이미지)
public interface EmotionAnalyzer {
    DiaryAnalysisResult analyze(String contentText, List<LlmImage> images);
}

// 저수준 LLM 호출 추상화 (provider 교체)
public interface LlmClient {
    LlmResponse complete(LlmRequest request);
}
// 구현: GeminiLlmClient, ClaudeLlmClient, OllamaLlmClient, StubLlmClient
//   (LlmConfig가 record.llm.provider·api-key 유무로 구현체를 프로그램적 선택)
```

- **설정**: `application.yml`의 `record.llm.*`(provider, model, api-key=환경변수, timeout-ms, max-retries). **기본 provider는 `gemini`**(무키 시 `StubLlmClient` 폴백, `LLM_PROVIDER=ollama`로 로컬 무키 전환 가능). **API 키는 환경변수(`LLM_API_KEY`)/시크릿으로 주입(코드·git 금지)**. ⚠️ 기본 모델은 `gemini-2.5-flash-lite`(thinking 미사용 → max-tokens 내 안정, 무료 등급 가능). `gemini-2.0-flash` 계열은 무료 등급이 막혀(429) 유료 키 전용이고, `gemini-2.5-flash`는 thinking 토큰이 출력을 잠식해 잘릴 수 있어 지양.
- **프롬프트**: "감정 분류 + 점수 분포 + 한줄 요약"을 **구조화 JSON 출력**으로 강제(파싱 안정성·토큰 절감).
- **비용 절감**: 입력 길이 상한·요약, 모델 티어 선택, 동일/유사 입력 단기 캐시(옵션).
- **타임아웃/재시도**: 클라이언트 레벨 타임아웃(`timeout-ms`). 네트워크 재시도는 Claude(Anthropic SDK)만 `max-retries` 적용하고, **Gemini/Ollama는 클라이언트 재시도 없이** 실패 시 폴백 후 `EmotionAnalysisPoller`(PENDING 백스톱)의 주기 재시도에 의존한다. (Resilience4j 서킷브레이커는 트래픽 증가 시 도입 — 초기엔 과함.)
- **폴백**: 실패 시 `primary_emotion=NEUTRAL`, 기본 테마/음악 적용, `analysis_status=FAILED` 기록 → 폴러가 PENDING을 재시도.

## 7. 감정 분석 동기 vs 비동기 (트레이드오프)

| 방식 | 장점 | 단점 |
|---|---|---|
| 동기(저장 시 LLM 대기) | 구현 단순, 결과 즉시 | 저장 2~5s 지연, LLM 장애 시 저장 실패, 타임아웃 UX 악화 |
| **비동기(권장)** | 저장 즉시 응답, LLM 장애 격리, 재시도 용이 | 상태(PENDING) 관리·클라 폴링 필요 |

**권장: 비동기 경량.** '등록'(confirm=false)은 `DRAFT`로 저장만 하고 **LLM을 호출하지 않는다**(수정 가능). '오늘을 기억하기'(confirm=true)로 **확정**하면 동기로 `PENDING` 즉시 반환 → `@Async`(전용 스레드풀) 또는 `ApplicationEvent` 리스너가 LLM 호출·테마/음악 매핑·`DONE` 갱신. 클라는 상세 재조회 또는 폴링. 외부 큐(SQS/Kafka)는 초기 불필요(트래픽 증가 시 도입). 분석은 트랜잭션 밖에서 수행하고 결과만 별도 트랜잭션으로 커밋.

- **확정 시 1회 분석**: 감정 분석은 **확정 시점(DRAFT→PENDING) 단 1회**만 수행한다. DRAFT 기록은 미분석 상태로 자유롭게 수정할 수 있지만, **확정된 기록은 수정 불가**(재upsert·`PUT` 모두 `DIARY_ALREADY_CONFIRMED`(409)). 따라서 "수정마다 재분석"하던 정책은 폐기됐고, 매 수정 LLM 호출로 인한 과부하가 제거된다. 확정 기록을 다시 쓰려면 삭제(소프트 삭제) 후 같은 날짜에 새로 작성한다.

## 8. 캐릭터 도메인 (Phase 7 구현본 — Task 026/027)

> 범위: **카탈로그 조회 · 캐릭터 선택 · 옷장 착용 · 미션 조회**. 보상 엔진(코인 적립·구매·미션 판정·보상함·리액션)은 **Task 028 미구현**(§2-1·§4-1).

### 8-1. group ↔ variant 2단 해석 (이 도메인의 핵심)

아이템은 **group**(소유·착용의 단위, `item_groups.code`)과 **variant**(렌더용 PNG, `character_items`의 `(group_code, character_code)` 조합)로 나뉜다. 소유·착용은 **group_code로만** 저장하고, 이미지는 **선택 캐릭터 기준으로 해석**해 내려준다. → 캐릭터를 바꿔도 `user_equipment`를 손대지 않고 **variant만 재해석**된다(옷장이 캐릭터를 따라오는 이유).

해석 규칙은 하나다: **캐릭터 전용 variant 우선 → 없으면 공용(`character_code IS NULL`) 폴백 → 둘 다 없으면 렌더 불가.** 이 규칙을 **두 경로로 구현**한다.

| 경로 | 구현 | 쓰는 곳 |
|---|---|---|
| **SQL 조인** | `SELECT DISTINCT ON (slot, slot_index) … ORDER BY …, ci.character_code NULLS LAST` — `NULLS LAST`가 곧 "전용 우선, 공용 폴백" | `UserCharacterMapper.findEquippedItems` (착용 목록) |
| **메모리 해석** | `CatalogCache.resolveVariant(groupCode, characterCode)` — `group_code → (캐릭터코드\|공용) → ResolvedVariant` 색인 | 검증(착용·캐릭터 교체), 아이템 목록 |

- 착용 **조회**는 해석 실패 행을 조용히 감추고, 착용·교체 **시점**에 `ITEM_VARIANT_MISSING`(409)으로 막는다.
- 아이템 목록은 내 캐릭터용 variant가 없는 그룹을 **제외**한다(그릴 수 없는 항목을 노출하지 않는다).

### 8-2. `CatalogCache` — 마스터 메모리 캐시

`characters`·`item_groups`·`character_items`·`missions`는 **마이그레이션으로만 바뀌는 마스터**라 매 요청 SQL을 태우지 않는다. 최초 접근 시 1회 지연 로딩(기동 순서·Flyway 의존을 만들지 않는다)하고, `render_meta`(JSONB) 파싱도 적재 시 1회만 수행해 `ResolvedVariant`로 굳힌다. 스냅샷은 **불변 객체를 volatile 참조로 통째 교체**한다 → 읽기 경로에 락이 없고, `reload()`(시드 변경 후 수동 갱신) 중에도 읽는 쪽은 이전 스냅샷을 일관되게 본다.

### 8-3. 기본 상태 JIT 생성 (멱등)

캐릭터 도메인의 **모든 진입점(조회 포함)** 은 `CharacterService.ensureState(userId)`를 먼저 통과한다 — `user_character_state`·`user_wallets`·`user_progress` 3행 + `DEFAULT` 아이템 소유를 심는다. 전부 `INSERT … ON CONFLICT DO NOTHING`이라 **멱등**하며(동시 최초요청 2건에도 각 1행), `UserProvisioningService`(Supabase JIT)와 **같은 철학**이다. → 신규 가입자도 빈 화면 대신 정상 응답을 받는다.

**캐릭터 미선택자도 `GET /characters/me`는 404가 아니라 200 + `character: null`** 이다. 이 null이 앱 온보딩 가드의 신호다(→ [`mobile.md`](./mobile.md) §7).

### 8-4. 미션 진행률은 O(1)

매 조회마다 `diaries`/`resolutions`를 세지 않는다. `MissionRuleType`별로 `user_progress` 스냅샷의 **컬럼 하나만** 읽는다 — `MissionService.progressOf(type, progress)`는 부작용 없는 **순수 함수**(static)라 Task 028의 `MissionEvaluator`가 그대로 재사용한다. 달성 판정·지급은 하지 않고, **이미 기록된 달성 이력(`user_missions`)과 현재 진행률만** 보여준다. (⚠️ `LEVEL` 규칙은 경험치/레벨 폐기(V18)로 제거 — 규칙은 4종.)

| 규칙 | 참조 컬럼 |
|---|---|
| `DIARY_COUNT` | `user_progress.confirmed_diary_count` |
| `CONSECUTIVE_DAYS` | `user_progress.consecutive_days` |
| `RESOLUTION_SUCCESS` | `user_progress.resolution_success_count` |
| `RESOLUTION_STREAK` | `user_progress.max_streak_seq` |

### 8-5. 착용 배치 교체는 원자적

`PUT /characters/me/equipment`는 보낸 배열이 **착용 전체 스냅샷**이다(빈 배열이면 전 슬롯 비움). 요청 전체를 **먼저 검증**하고 하나라도 실패하면 **쓰기 전에** 예외를 던진다 → "5개 중 3번째가 미보유면 1·2번도 반영 안 됨"이 자명하게 성립한다. 통과한 경우에만 `DELETE`→`INSERT`를 한 트랜잭션에서 수행한다.

검증 순서는 고정이다: **슬롯 규칙(400) → 슬롯 일치(400) → 소유(409) → variant(409).** DB 제약(`chk_user_equipment_slot_index`, 복합 FK)은 최종 방어선일 뿐이고, 서비스가 먼저 걸러 `SQLException`이 새지 않게 한다.

- `ROOM_PROP`만 다중 진열(`slot_index` 0~5, Rive `roomProp0..5`와 1:1)이고 나머지 슬롯은 0번 한 칸뿐이다(`ItemSlot.maxSlotIndex()`).
- 같은 칸 중복·같은 group 두 칸 진열은 PK/`uq_user_equipment_group` 충돌 전에 400으로 선방어한다.

### 8-6. ErrorCode (신규 4종)

`global/exception/ErrorCode.java`에 추가됐다.

| 코드 | HTTP | 의미 |
|---|---|---|
| `CHARACTER_NOT_OWNED` | 409 | 선택할 수 없는 캐릭터. 캐릭터는 전원 무료 개방이라 **없는/비활성 코드도 여기로 수렴**시킨다 |
| `ITEM_NOT_OWNED` | 409 | 미보유 아이템 착용(존재하지 않는 group도 여기로 수렴) |
| `ITEM_SLOT_MISMATCH` | 400 | 해당 부위에 착용할 수 없는 아이템 |
| `ITEM_VARIANT_MISSING` | 409 | `(group, 선택 캐릭터)` variant 미제작 — 착용·캐릭터 교체 양쪽에서 발생 |

> 캐릭터 **교체 시에도** 착용 중인 group 전부를 선검증해 하나라도 미제작이면 `ITEM_VARIANT_MISSING`으로 **교체를 거부**한다. 허용하면 홈이 그 아이템을 못 그린 채 조용히 사라지므로, 원인을 명시적으로 알린다.

### 8-7. IDOR 차단

경로·바디에 **사용자 식별자가 없다.** 소유권은 언제나 SecurityContext의 내부 `userId`로만 식별한다(`@AuthenticationPrincipal SecurityUser`). 매퍼의 모든 조회/수정도 `userId`로 대상을 좁힌다.
