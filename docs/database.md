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

-- ========== 일기 기록 ==========
-- [V2__add_diaries.sql] Task 008(일기 CRUD)에서 생성. users(id) FK라 users(V1) 이후 적용.
CREATE TABLE diaries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    share_token     UUID NOT NULL DEFAULT gen_random_uuid(),    -- 공유 링크용
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    written_date    DATE NOT NULL,                              -- 기록 대상 날짜
    visibility      VARCHAR(20) NOT NULL DEFAULT 'PRIVATE',     -- PRIVATE/FRIENDS/PUBLIC
    analysis_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',     -- PENDING/DONE/FAILED
    theme_id        BIGINT REFERENCES themes(id),               -- 적용 테마 스냅샷
    track_id        BIGINT REFERENCES tracks(id),               -- 적용 음악 스냅샷
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT uq_diaries_share_token UNIQUE (share_token)
);
-- 하루 1기록 제한(수정은 동일 행 UPDATE) — 소프트 삭제분 제외
CREATE UNIQUE INDEX uq_diary_user_day ON diaries(user_id, written_date) WHERE deleted_at IS NULL;
-- 내 일기 목록(최신순)
CREATE INDEX idx_diaries_user_date ON diaries(user_id, written_date DESC) WHERE deleted_at IS NULL;
-- 공개 피드
CREATE INDEX idx_diaries_visibility_created ON diaries(visibility, created_at DESC) WHERE deleted_at IS NULL;

-- ========== 감정 분석 결과 (diary 1:1) ==========
CREATE TABLE emotion_analyses (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diary_id        BIGINT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
    primary_emotion VARCHAR(20) NOT NULL REFERENCES emotion_types(code),
    emotion_scores  JSONB,                      -- {"JOY":0.7,"CALM":0.2,...}
    confidence      NUMERIC(4,3),               -- 0.000~1.000
    summary         TEXT,                       -- LLM 한줄 요약
    llm_provider    VARCHAR(30),                -- CLAUDE/OPENAI
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
```

## 5. 주요 설계 결정

- **DB는 별도 PostgreSQL(Supabase 미사용)**: 앱 데이터는 Supabase와 무관한 별도 PostgreSQL에 저장한다(로컬: Docker, 배포: 관리형/자체호스팅). Supabase는 **Auth 전용**이며, 인증↔데이터는 `users.supabase_uid` 컬럼 매핑으로만 연결한다(`auth.users` FK·RLS·트리거 미사용 — 물리적으로 다른 DB).
- **Supabase Auth 매핑**: 소셜 로그인·세션(access/refresh)은 Supabase Auth가 관리하고, 백엔드는 `users.supabase_uid`(= Supabase `auth.users.id`, JWT `sub`)로 1:1 매핑한다. 별도 `social_accounts`/`refresh_tokens` 테이블을 두지 않으며, 최초 인증 요청 시 `users` 행을 자동 생성(JIT 프로비저닝)한다. `users.uuid`(외부 공유 노출용)와 `supabase_uid`(인증 매핑용)는 용도가 다른 별개 식별자다.
- **하루 1기록 + 수정**: `uq_diary_user_day` 부분 유니크 인덱스로 사용자·날짜당 1행 강제. 동일 날짜 재작성은 신규 INSERT가 아닌 **UPDATE**로 처리하고, 내용 변경 시 감정 분석을 재실행해 `theme_id`/`track_id`를 갱신한다.
- **테마/음악 스냅샷**: `diaries.theme_id`·`track_id`를 결과로 저장해, 추후 프리셋(themes/tracks)이 바뀌어도 과거 기록의 분위기는 보존된다.
- **음악 소스 추상화**: `tracks.source_type` + `source_ref` + `metadata(JSONB)`로 자체 음원·외부 API(Spotify/YouTube) 어느 쪽이든 동일 테이블로 수용.
- **공감만**: `diary_reactions`에 `uq_reaction_once`로 1인 1회 공감. 댓글 테이블은 의도적으로 생략(모더레이션 복잡도 회피).

## 6. Flyway 운영 방침

- 스키마 변경은 MyBatis와 무관하게 Flyway로 버전 관리. 이 문서(§4)는 **최종 목표 전체 스키마**를 한곳에 모은 통합 뷰이고, 실제 적용은 **기능 구현 단위로 마이그레이션 파일을 하나씩 추가**한다("구현 때마다 테이블 하나씩").
- **마이그레이션 분할 매핑**:
  - `V1__init.sql` — `users` (인증·프로필. 본 단계)
  - `V2__add_diaries.sql` — `diaries` (Task 008, 일기 CRUD)
  - 이후 감정/테마/음악/사회 도메인은 구현 시점에 `Vn__*.sql`로 추가. 마스터 데이터(`emotion_types`, 초기 `themes`/`tracks`)는 별도 `Vn__seed_*.sql`로 분리.
- **로컬 개발**: 네이티브 PostgreSQL 18(`recorme` DB/롤)에 빈 DB만 준비하면 `./gradlew bootRun` 시 Flyway가 자동 적용. DBeaver는 조회용. 도커는 배포 시점(Task 016)에 사용.
- 운영 환경에서는 `flyway.clean` 비활성화(`clean-disabled=true`), 모든 변경은 신규 버전 마이그레이션으로만(기배포된 Vn은 수정 금지 — 미배포 단계에서만 V1 직접 재작성 허용).
