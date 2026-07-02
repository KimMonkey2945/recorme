# record 데이터베이스 설계 (PostgreSQL)

> 전체 DDL과 ERD, PK/인덱스 전략. 스키마 버전은 Flyway로 관리한다.

## 1. 도메인 식별

| 그룹 | 테이블 | 설명 |
|---|---|---|
| 회원 | `users` | 사용자 (Supabase Auth 사용자와 `supabase_uid`로 매핑) |
| 기록 | `diaries` | 하루 기록(하루 1개, 수정 가능) |
| 감정 | `emotion_types` | 감정 코드 마스터 |
| | `emotion_analyses` | LLM 감정 분석 결과(diary 1:1) |
| 테마 | `themes` | 감정별 테마 프리셋(배경·필체) |
| 음악 | `tracks` | 음악 트랙(소스 추상화) |
| | `emotion_track_map` | 감정 → 트랙 매핑 |
| 사회적 | `friendships` | 친구 관계 |
| | `diary_reactions` | 공감(리액션) — 댓글 없음 |
| 작심삼일 | `resolutions` | 3일 결심(시작일·할일·상태·연장 체인) |
| | `resolution_checks` | 결심의 일별 체크(3일치, 완료/미완료) |
| 알림 | `device_tokens` | FCM 기기 토큰(서버 푸시 팬아웃) |

## 2. ERD (관계 개요)

```
(소셜 계정·refresh 토큰은 Supabase Auth가 관리 → 백엔드 테이블 없음. users.supabase_uid로 매핑)
users 1───∞ diaries
users 1───∞ friendships (requester / addressee, 양방향)
users 1───∞ diary_reactions

diaries 1───1 emotion_analyses
diaries ∞───1 themes        (적용 테마 스냅샷, nullable)
diaries ∞───1 tracks        (적용 음악 스냅샷, nullable)
diaries 1───∞ diary_reactions

emotion_types 1───∞ themes
emotion_types 1───∞ emotion_track_map ∞───1 tracks
emotion_types 1───∞ emotion_analyses (primary_emotion)

users 1───∞ resolutions 1───∞ resolution_checks   (연장은 streak_group_id UUID 체인으로 self-묶음)
users 1───∞ resolution_checks                      (캘린더 직접조회용 비정규화 FK)
users 1───∞ device_tokens
```

## 3. 설계 규칙

- **PK 전략**: 내부 PK는 `BIGINT GENERATED ALWAYS AS IDENTITY`(인덱스·조인·저장공간 우위). 외부 노출용은 `users.uuid`, `diaries.share_token`(UUID) — URL/공유 시 순차 ID 추측(enumeration) 방지.
- **네이밍**: snake_case(PostgreSQL 관례).
- **타임스탬프**: `TIMESTAMPTZ`, 감사 컬럼 `created_at DEFAULT now()` / `updated_at`.
- **소프트 삭제**: `deleted_at` (물리 삭제 대신 보존).
- `gen_random_uuid()` 사용 위해 PostgreSQL 13+ 내장 또는 `pgcrypto`.

## 4. 전체 DDL

```sql
-- ========== 회원 ==========
-- [V1__init.sql] 회원 마스터. 이메일·소셜(카카오/구글) 가입자 모두 동일 테이블에 JIT 저장.
CREATE TABLE users (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid              UUID NOT NULL DEFAULT gen_random_uuid(),   -- 외부 노출용 식별자(공유 등)
    supabase_uid      UUID NOT NULL,                             -- Supabase auth.users.id 매핑(JWT sub)
    nickname          VARCHAR(50) NOT NULL,
    email             VARCHAR(255),                              -- 소셜 미제공 가능 → nullable
    profile_image_url TEXT,                                      -- 이미지 참조(경로/URL)만, 바이너리 아님. 내부 업로드=상대경로(/files/avatars/...), 외부 소셜=절대 URL. 호스트는 앱이 조립
    bio               VARCHAR(300),                              -- 자기소개(프로필 수정 대상, nullable)
    status            VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',     -- ACTIVE/DORMANT/WITHDRAWN
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    CONSTRAINT uq_users_uuid UNIQUE (uuid),
    CONSTRAINT uq_users_supabase_uid UNIQUE (supabase_uid)
);
-- 이메일 중복 방지(활성 행 한정, 대소문자 무시). 소셜 미제공(NULL)·탈퇴(soft delete)분은 제외.
CREATE UNIQUE INDEX uq_users_email_active
    ON users (lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL;

-- 소셜 계정·리프레시 토큰 테이블 없음:
--   소셜 로그인 검증과 세션(access/refresh) 관리는 Supabase Auth가 전담한다.
--   백엔드는 users.supabase_uid 로 Supabase 사용자를 매핑하고, 최초 인증 요청 시
--   JWT 클레임(email)·user_metadata(닉네임/프로필)로 users 행을 JIT 프로비저닝한다.
--   이메일 가입도 Supabase가 동일 형식의 access token을 발급하므로 백엔드 분기 없이 같은 경로로 처리된다.

-- ========== 감정 타입 마스터 ==========
CREATE TABLE emotion_types (
    code       VARCHAR(20) PRIMARY KEY,        -- JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL ...
    label_ko   VARCHAR(30) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0
);

-- ========== 테마 프리셋 (감정별) ==========
CREATE TABLE themes (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emotion_code     VARCHAR(20) NOT NULL REFERENCES emotion_types(code),
    name             VARCHAR(50) NOT NULL,
    background_type  VARCHAR(20) NOT NULL,     -- COLOR/GRADIENT/IMAGE
    background_value TEXT NOT NULL,            -- hex, gradient json, asset key
    font_family      VARCHAR(50) NOT NULL,     -- 앱 번들 폰트 키
    text_color       VARCHAR(9) NOT NULL,      -- #RRGGBBAA
    is_active        BOOLEAN NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_themes_emotion ON themes(emotion_code) WHERE is_active;

-- ========== 음악 트랙 (소스 추상화) ==========
CREATE TABLE tracks (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_type  VARCHAR(20) NOT NULL,         -- LOCAL_FILE/SPOTIFY/YOUTUBE
    source_ref   VARCHAR(255) NOT NULL,        -- 파일키 또는 외부 트랙 ID
    title        VARCHAR(200),
    artist       VARCHAR(200),
    stream_url   TEXT,                          -- 재생/미리듣기 URL(소스에 따라 nullable)
    duration_sec INT,
    metadata     JSONB,                         -- 소스별 부가정보
    is_active    BOOLEAN NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_tracks_source UNIQUE (source_type, source_ref)
);

-- 감정 → 트랙 매핑(감정당 다수 후보, weight로 선택)
CREATE TABLE emotion_track_map (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emotion_code VARCHAR(20) NOT NULL REFERENCES emotion_types(code),
    track_id     BIGINT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    weight       INT NOT NULL DEFAULT 1,
    CONSTRAINT uq_emotion_track UNIQUE (emotion_code, track_id)
);
CREATE INDEX idx_emotion_track_emotion ON emotion_track_map(emotion_code);

-- ========== 기록 (diaries) ==========
-- [V2__add_diaries.sql] Task 008(기록 CRUD)에서 생성. users(id) FK라 users(V1) 이후 적용.
-- ⚠️ MVP 실제 적용본(V2)은 theme_id/track_id 및 공개 피드 인덱스(idx_diaries_visibility_created)를
--    제외한다(Phase 4에서 ALTER/추가). 아래는 최종 목표 스키마 통합 뷰이며, theme_id/track_id 줄은 Phase 4 표시.
CREATE TABLE diaries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    share_token     UUID NOT NULL DEFAULT gen_random_uuid(),    -- 공유 링크용
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    written_date    DATE NOT NULL,                              -- 기록 대상 날짜
    visibility      VARCHAR(20) NOT NULL DEFAULT 'PRIVATE',     -- PRIVATE/FRIENDS/PUBLIC (enum 검증은 앱·백엔드)
    analysis_status VARCHAR(20) NOT NULL DEFAULT 'DRAFT',       -- DRAFT/PENDING/DONE/FAILED (enum 검증은 앱·백엔드·CHECK). DRAFT=미확정(수정가능·미분석), PENDING=확정·분석대기
    theme_id        BIGINT REFERENCES themes(id),               -- [Phase 4] 적용 테마 스냅샷 (V2 미포함)
    track_id        BIGINT REFERENCES tracks(id),               -- [Phase 4] 적용 음악 스냅샷 (V2 미포함)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT uq_diaries_share_token UNIQUE (share_token),
    -- 본문 길이 1~500: 백엔드 DiaryConstraints.CONTENT_MAX · 앱 maxLength 와 동일 상수(LLM 비용·품질 가드).
    CONSTRAINT chk_diaries_content_len CHECK (char_length(content) BETWEEN 1 AND 500)
);
-- 하루 1기록 제한(수정은 동일 행 UPDATE) — 소프트 삭제분 제외
CREATE UNIQUE INDEX uq_diary_user_day ON diaries(user_id, written_date) WHERE deleted_at IS NULL;
-- 내 기록 목록(최신순)
CREATE INDEX idx_diaries_user_date ON diaries(user_id, written_date DESC) WHERE deleted_at IS NULL;
-- 공개 피드 [Phase 4] (friendships 등장 시점에 추가 — V2 미포함)
CREATE INDEX idx_diaries_visibility_created ON diaries(visibility, created_at DESC) WHERE deleted_at IS NULL;

-- ========== 기록 첨부 사진 (diary 1:N) ==========
-- [V3__add_diary_images.sql] Task 008(사진 첨부)에서 생성. diaries(id) FK라 diaries(V2) 이후 적용.
-- 바이너리는 스토리지(로컬 디스크→S3)에 두고 DB엔 상대경로(/files/diaries/yyyy/MM/{uuid}.ext)만 저장.
-- 기록당 최대 5장(서비스 레이어 검증, DB 트리거 미사용). 소프트삭제 컬럼 없음 — 삭제 시 행+디스크 파일 즉시 회수.
CREATE TABLE diary_images (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diary_id   BIGINT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
    image_url  TEXT NOT NULL,                                  -- 스토리지 상대경로
    sort_order INT NOT NULL DEFAULT 0,                         -- 표시 순서(0부터)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_diary_images_diary ON diary_images(diary_id, sort_order);

-- ========== 감정 분석 결과 (diary 1:1) ==========
CREATE TABLE emotion_analyses (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diary_id        BIGINT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
    primary_emotion VARCHAR(20) NOT NULL REFERENCES emotion_types(code),
    emotion_scores  JSONB,                      -- {"JOY":0.7,"CALM":0.2,...}
    confidence      NUMERIC(4,3),               -- 0.000~1.000
    summary         TEXT,                       -- LLM 한줄 요약
    llm_provider    VARCHAR(30),                -- GEMINI/CLAUDE/OLLAMA/STUB
    llm_model       VARCHAR(50),
    raw_response    JSONB,                       -- 원본(디버깅/재처리용)
    analyzed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_emotion_analysis_diary UNIQUE (diary_id)
);

-- ========== 친구 관계 ==========
CREATE TABLE friendships (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requester_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    addressee_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       VARCHAR(20) NOT NULL DEFAULT 'PENDING',        -- PENDING/ACCEPTED/BLOCKED
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,
    CONSTRAINT uq_friendship_pair UNIQUE (requester_id, addressee_id),
    CONSTRAINT chk_no_self_friend CHECK (requester_id <> addressee_id)
);
CREATE INDEX idx_friendships_addressee ON friendships(addressee_id, status);
CREATE INDEX idx_friendships_requester ON friendships(requester_id, status);

-- ========== 공감(리액션) — 댓글 없음 ==========
CREATE TABLE diary_reactions (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diary_id   BIGINT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type       VARCHAR(20) NOT NULL DEFAULT 'EMPATHY',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_reaction_once UNIQUE (diary_id, user_id, type)
);
CREATE INDEX idx_diary_reactions_diary ON diary_reactions(diary_id);

-- ========== 작심삼일 (결심) ==========
-- [V9__add_resolutions.sql] 3일 결심 + 일별 체크 한 세트. users(id) FK라 users(V1) 이후 적용.
-- 상태: ONGOING → SUCCESS | FAILED(터미널). '예정'(미래 시작)은 별도 상태 없이 start_date > today 로 파생,
--       취소는 soft delete(deleted_at). 상태 전이는 서비스/배치가 수행(DB 트리거 미사용).
CREATE TABLE resolutions (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title            VARCHAR(100) NOT NULL,                     -- 할일 제목(1~100자)
    start_date       DATE NOT NULL,                             -- 시작일(오늘/미래, 과거 금지는 서비스 검증)
    end_date         DATE NOT NULL,                             -- 종료일 = start_date + 2 (3일)
    status           VARCHAR(20) NOT NULL DEFAULT 'ONGOING',    -- ONGOING/SUCCESS/FAILED
    reminder_time    TIME,                                      -- 매일 알림 시각(KST 벽시계). NULL=알림 없음
    streak_group_id  UUID NOT NULL DEFAULT gen_random_uuid(),   -- 연장 체인 묶음(첫 도전 생성, 연장 시 복사)
    streak_seq       SMALLINT NOT NULL DEFAULT 1,               -- 체인 내 순번(1부터, 연장 시 +1) = "N연속"
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ,
    -- title 1~100: 백엔드 ResolutionConstraints.TITLE_MAX 와 동일 상수.
    CONSTRAINT chk_resolutions_title_len  CHECK (char_length(title) BETWEEN 1 AND 100),
    -- 3일 span 불변식(불변 표현이라 CHECK 가능). '시작일 오늘/미래'는 비불변이라 서비스 검증.
    CONSTRAINT chk_resolutions_span       CHECK (end_date = start_date + 2),
    CONSTRAINT chk_resolutions_status     CHECK (status IN ('ONGOING','SUCCESS','FAILED')),
    CONSTRAINT chk_resolutions_streak_seq CHECK (streak_seq >= 1),
    -- 같은 체인 내 순번 중복(동시 이중 연장 경합) 방지.
    CONSTRAINT uq_resolutions_streak_seq  UNIQUE (streak_group_id, streak_seq)
);
-- 리스트(진행/성공/실패 탭 + 최신순 커서). user_id·status 등치 후 (start_date,id) 정렬 무료.
CREATE INDEX idx_resolutions_user_status_start
    ON resolutions (user_id, status, start_date DESC, id DESC) WHERE deleted_at IS NULL;

-- ========== 작심삼일 일별 체크 (resolution 1:3) ==========
-- resolution 생성 시 3행(day_index 1~3, check_date = start_date + 0/1/2)을 PENDING 으로 프리생성.
-- user_id 는 월 캘린더를 단일 테이블 range scan 으로 끝내기 위한 비정규화(부모 조인 없이 조회).
-- deleted_at 없음: 부모 soft delete 시 캘린더 쿼리가 r.deleted_at IS NULL 로 거르고, 물리 삭제 시 FK CASCADE 로 정리.
CREATE TABLE resolution_checks (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resolution_id  BIGINT NOT NULL REFERENCES resolutions(id) ON DELETE CASCADE,
    user_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- 캘린더 직접조회용 비정규화
    check_date     DATE NOT NULL,                             -- 이 체크가 속한 날짜
    day_index      SMALLINT NOT NULL,                         -- 1..3 (1·2·3일차)
    status         VARCHAR(20) NOT NULL DEFAULT 'PENDING',    -- PENDING/DONE/MISSED
    completed_at   TIMESTAMPTZ,                               -- DONE 전이 시각(NULL=미완료)
    reminded_on    DATE,                                      -- 리마인더 발송한 날짜(하루 1회 멱등 선점 키)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_resolution_checks_day    CHECK (day_index BETWEEN 1 AND 3),
    CONSTRAINT chk_resolution_checks_status CHECK (status IN ('PENDING','DONE','MISSED')),
    -- 상태-데이터 정합: DONE 이면 완료시각 필수(PENDING/MISSED 는 NULL 허용).
    CONSTRAINT chk_resolution_checks_done   CHECK (status <> 'DONE' OR completed_at IS NOT NULL),
    CONSTRAINT uq_resolution_checks_day     UNIQUE (resolution_id, check_date),  -- 하루 1체크(중복·경합 방지)
    CONSTRAINT uq_resolution_checks_idx     UNIQUE (resolution_id, day_index)    -- 3행 프리생성 무결성
);
-- 월별 캘린더: 특정 유저의 월 구간 체크를 단일 테이블 range scan 으로.
CREATE INDEX idx_resolution_checks_user_date ON resolution_checks (user_id, check_date);
-- 자정 실패배치(check_date < today) + FCM 리마인더(check_date = today) 공용.
-- PENDING 행만 얇게 인덱싱 → 남은 미완료만 스캔(부분 인덱스로 배치 비용 상수 유지).
CREATE INDEX idx_resolution_checks_pending ON resolution_checks (check_date) WHERE status = 'PENDING';

-- ========== FCM 기기 토큰 (서버 푸시) ==========
-- [V10__add_device_tokens.sql] 알림 인프라. 작심삼일 리마인더 외 알림에도 재사용될 범용 테이블.
-- token 은 기기당 1개(전역 유일). 재로그인/재설치 시 upsert 로 소유 재귀속.
-- 무효 토큰(FCM UNREGISTERED/INVALID_ARGUMENT)은 물리 DELETE(회수형, soft delete 없음).
-- 내부 전용 테이블이라 외부 노출 uuid 는 생략(diary_images 관례).
CREATE TABLE device_tokens (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token         TEXT NOT NULL,                             -- FCM registration token
    platform      VARCHAR(20) NOT NULL,                      -- ANDROID/IOS/WEB
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),        -- 최근 등록/갱신(스테일 토큰 정리 기준)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_device_tokens_token     UNIQUE (token),
    CONSTRAINT chk_device_tokens_platform CHECK (platform IN ('ANDROID','IOS','WEB'))
);
-- 유저 팬아웃(리마인더 발송 시 user_id → 토큰들) 조회용.
CREATE INDEX idx_device_tokens_user ON device_tokens (user_id);
```

## 5. 주요 설계 결정

- **DB는 별도 PostgreSQL(Supabase 미사용)**: 앱 데이터는 Supabase와 무관한 별도 PostgreSQL에 저장한다(로컬: Docker, 배포: 관리형/자체호스팅). Supabase는 **Auth 전용**이며, 인증↔데이터는 `users.supabase_uid` 컬럼 매핑으로만 연결한다(`auth.users` FK·RLS·트리거 미사용 — 물리적으로 다른 DB).
- **Supabase Auth 매핑**: 소셜 로그인·세션(access/refresh)은 Supabase Auth가 관리하고, 백엔드는 `users.supabase_uid`(= Supabase `auth.users.id`, JWT `sub`)로 1:1 매핑한다. 별도 `social_accounts`/`refresh_tokens` 테이블을 두지 않으며, 최초 인증 요청 시 `users` 행을 자동 생성(JIT 프로비저닝)한다. `users.uuid`(외부 공유 노출용)와 `supabase_uid`(인증 매핑용)는 용도가 다른 별개 식별자다.
- **하루 1기록 + draft→확정 라이프사이클**: `uq_diary_user_day` 부분 유니크 인덱스로 사용자·날짜당 1행 강제. 동일 날짜 재작성은 신규 INSERT가 아닌 **UPDATE**로 처리한다. `analysis_status`가 `DRAFT`인 기록만 수정 가능하며, '오늘을 기억하기'로 **확정(`PENDING`)하면 감정 분석을 1회 수행**한다. **확정 후에는 수정 불가**(재upsert·PUT 모두 409 `DIARY_ALREADY_CONFIRMED`)이며, **삭제는 허용**한다(소프트 삭제 → 같은 날짜 재작성 가능). 매 수정마다 LLM을 호출하던 과부하를 피하기 위해 분석을 확정 시점 1회로 한정한다.
- **테마/음악 스냅샷**: `diaries.theme_id`·`track_id`를 결과로 저장해, 추후 프리셋(themes/tracks)이 바뀌어도 과거 기록의 분위기는 보존된다.
- **음악 소스 추상화**: `tracks.source_type` + `source_ref` + `metadata(JSONB)`로 자체 음원·외부 API(Spotify/YouTube) 어느 쪽이든 동일 테이블로 수용.
- **공감만**: `diary_reactions`에 `uq_reaction_once`로 1인 1회 공감. 댓글 테이블은 의도적으로 생략(모더레이션 복잡도 회피).
- **작심삼일 상태 모델**: `resolutions.status`는 `ONGOING → SUCCESS | FAILED`(SUCCESS/FAILED는 터미널). **'예정'(미래 시작)은 별도 상태를 두지 않고 `start_date > 오늘`로 파생**해 상태 수를 줄인다. **취소는 소프트 삭제**(`deleted_at`)로 처리해 물리 삭제와 구분한다. 상태 전이는 서비스/배치가 수행하고 DB 트리거는 쓰지 않는다(`SUCCESS`는 3일 완주 시 `status='ONGOING'` 가드로 1회, `FAILED`는 자정 배치가 초과 미완료 발견 시).
- **연장 체인(streak)**: 성공한 결심을 '다음 3일'로 이을 때 새 `resolutions` 행을 만들되 `streak_group_id`(UUID)를 복사하고 `streak_seq`를 +1 한다. 같은 체인 내 `(streak_group_id, streak_seq)` **UNIQUE**로 동시 이중 연장 경합을 막고(서비스 선검사 + 제약 최종 방어), `streak_seq`가 "N연속"을 뜻한다. 첫 도전은 `gen_random_uuid()`로 새 체인·`seq=1`.
- **하루 1체크 + 3행 프리생성**: `resolution_checks`는 결심 생성 시 3행(`day_index` 1~3)을 `PENDING`으로 미리 만든다. `uq_resolution_checks_day(resolution_id, check_date)`로 하루 1체크(중복·경합 차단), `uq_resolution_checks_idx(resolution_id, day_index)`로 3행 무결성을 강제한다. `DONE`이면 `completed_at` 필수(CHECK 정합).
- **`resolution_checks.user_id` 비정규화**: 월별 캘린더를 `resolutions` 조인 없이 `resolution_checks` **단일 테이블 range scan**(`idx_resolution_checks_user_date`)으로 끝내기 위해 부모의 `user_id`를 복사한다. 부모 소프트 삭제분은 캘린더 쿼리가 `r.deleted_at IS NULL`로 걸러 정합을 유지한다.
- **리마인더 멱등(`reminded_on`)**: 오늘자 리마인더는 `reminded_on = 오늘`로 마킹해 하루 1회만 발송한다. 선점+마킹을 한 문장(CTE + `FOR UPDATE ... SKIP LOCKED`)으로 처리해 다중 인스턴스 배치가 같은 행을 중복 발송하지 않는다. `idx_resolution_checks_pending`(부분 인덱스)로 남은 미완료만 스캔해 자정 실패 배치·리마인더의 스캔 비용을 상수로 유지한다.
- **기기 토큰(FCM)**: `device_tokens.token`은 전역 UNIQUE(기기당 1개)라 재로그인/재설치 시 **upsert로 소유를 재귀속**한다. 무효 토큰은 물리 DELETE(회수형, 소프트 삭제 없음). 작심삼일 리마인더·완주 축하 외 다른 알림에도 재사용될 범용 테이블이며 내부 전용이라 외부 노출 UUID는 생략한다.

## 6. Flyway 운영 방침

- 스키마 변경은 MyBatis와 무관하게 Flyway로 버전 관리. 이 문서(§4)는 **최종 목표 전체 스키마**를 한곳에 모은 통합 뷰이고, 실제 적용은 **기능 구현 단위로 마이그레이션 파일을 하나씩 추가**한다("구현 때마다 테이블 하나씩").
- **마이그레이션 분할 매핑**:
  - `V1__init.sql` — `users` (인증·프로필. 본 단계)
  - `V2__add_diaries.sql` — `diaries` (Task 008, 기록 CRUD). MVP 스코프상 `theme_id`/`track_id`·공개 피드 인덱스 제외, `chk_diaries_content_len`(1~500) 포함.
  - `V3__add_diary_images.sql` — `diary_images` (Task 008, 사진 첨부 1:N)
  - `V8__diary_draft_lifecycle.sql` — `diaries.analysis_status` 기본값을 `'PENDING'` → **`'DRAFT'`**로 변경하고 `CHECK (analysis_status IN ('DRAFT','PENDING','DONE','FAILED'))` 제약 추가(기록 draft→확정 라이프사이클). 기존 데이터 백필 없음.
  - `V9__add_resolutions.sql` — `resolutions` + `resolution_checks` (작심삼일 3일 결심 + 일별 체크 한 세트)
  - `V10__add_device_tokens.sql` — `device_tokens` (FCM 서버 푸시 기기 토큰)
  - 이후 감정/테마/음악/사회 도메인은 구현 시점에 `Vn__*.sql`로 추가(예: `diaries.theme_id`/`track_id`는 Phase 4에서 `ALTER TABLE ADD COLUMN`). 마스터 데이터(`emotion_types`, 초기 `themes`/`tracks`)는 별도 `Vn__seed_*.sql`로 분리.
  - (참고) 그 사이 마이그레이션: `V4=리치 본문(content=Delta JSON·content_text)`, `V5=diary_images 제거`, `V6=content_text NOT NULL`, `V7=emotion_analyses`, `V8=draft→확정 라이프사이클`.
- **로컬 개발**: 네이티브 PostgreSQL 18(`recorme` DB/롤)에 빈 DB만 준비하면 `./gradlew bootRun` 시 Flyway가 자동 적용. DBeaver는 조회용. 도커는 배포 시점(Task 016)에 사용.
- 운영 환경에서는 `flyway.clean` 비활성화(`clean-disabled=true`), 모든 변경은 신규 버전 마이그레이션으로만(기배포된 Vn은 수정 금지 — 미배포 단계에서만 V1 직접 재작성 허용).
