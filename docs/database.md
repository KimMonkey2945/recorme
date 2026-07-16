# record 데이터베이스 설계 (PostgreSQL)

> 전체 DDL과 ERD, PK/인덱스 전략. 스키마 버전은 Flyway로 관리한다.

## 1. 도메인 식별

| 그룹 | 테이블 | 설명 |
|---|---|---|
| 회원 | `users` | 사용자 (Supabase Auth 사용자와 `supabase_uid`로 매핑). 친구코드 `friend_code`(V11) 포함 |
| 기록 | `diaries` | 하루 기록(하루 1개, 수정 가능). 감정·색·공감수 컬럼을 **직접 보유**(V7·V14) |
| 감정 | `emotion_types` | 감정 코드 마스터 6종(감정 코드의 단일 진실원) |
| 캐릭터 | `characters` | 캐릭터 마스터(MONKEY·RED_PANDA, V15 시드 2종) |
| | `item_groups` | 아이템 **소유·착용·상점 단위**(예: "빨간 후드티") |
| | `character_items` | 아이템 **렌더 단위(variant)** — `(group_code, character_code)` 조합별 이미지 |
| | `character_lines` | 캐릭터 대사(맥락별 — 감정 아님) |
| | `missions` / `user_missions` | 미션(업적) 마스터 + 달성 이력 — **유일한 해금 경로** |
| | `user_character_state` | 선택 캐릭터 (레벨·경험치는 V18 보상 재설계에서 드롭) |
| | `user_item_groups` / `user_equipment` | 아이템 소유(group 단위) / 착용 슬롯 |
| | `user_progress` | 미션 판정용 진척도 캐시(O(1)) |
| | `user_wallets` | 코인 잔액 |
| | `character_events` | **멱등 관문 + 코인 원장 + 리액션 페이로드 + 보상 알림함** |
| 사회적 | `friendships` | 친구 관계 |
| | `diary_reactions` | 공감(리액션) — 댓글 없음 |
| 작심삼일 | `resolutions` | 3일 결심(시작일·할일·상태·연장 체인) |
| | `resolution_checks` | 결심의 일별 체크(3일치, 완료/미완료) |
| 알림 | `device_tokens` | FCM 기기 토큰(서버 푸시 팬아웃) |

> ⚠️ **문서 정정(구현 기준)**: 초기 설계에 있던 `emotion_analyses`(diary 1:1) · `themes` · `tracks` · `emotion_track_map` 테이블은 **실제로 존재하지 않는다**.
> - `emotion_analyses` → **V7이 `diaries`에 분석 컬럼을 직접 추가**하는 방식으로 대체됐다(1:1 조인 제거).
> - `themes`(고정 테마 프리셋) → 감정별 색을 LLM이 일기마다 자유 생성해 `diaries`에 스냅샷으로 저장하는 방식으로 대체됐고, **Phase 7에서 감정 시각 연출 자체가 폐기**되어 도입 계획이 사라졌다.
> - `tracks` / `emotion_track_map`(감정 기반 음악) → **MVP 이후 범위**로 미구현이며, Phase 7 전환(캐릭터 중심)으로 우선순위에서 내려갔다.

## 2. ERD (관계 개요)

```
(소셜 계정·refresh 토큰은 Supabase Auth가 관리 → 백엔드 테이블 없음. users.supabase_uid로 매핑)

── 회원 · 기록 ──────────────────────────────────────────────
users 1───∞ diaries                (users.friend_code = 친구코드, V11)
users 1───∞ friendships (requester / addressee, 양방향)
users 1───∞ diary_reactions ∞───1 diaries   (diaries.reaction_count = 비정규화 캐시, V14)

emotion_types 1───∞ diaries (primary_emotion FK, nullable)
    ※ diaries가 감정·색·AI 필드를 직접 보유(V7). emotion_analyses 1:1 테이블은 없다.
    ※ 감정은 기본적으로 **사용자 직접 입력**이다(프리셋 primary_emotion FK 또는 자유 텍스트 emotion_label).
      LLM 비동기 분석은 flag(record.analysis.enabled, 기본 false)로 꺼져 있고 true 시 복구된다 — Task 024(V19) 적용됨.

── 작심삼일 · 알림 ──────────────────────────────────────────
users 1───∞ resolutions 1───∞ resolution_checks   (연장은 streak_group_id UUID 체인으로 self-묶음)
users 1───∞ resolution_checks                      (캘린더 직접조회용 비정규화 FK)
users 1───∞ device_tokens

── 캐릭터 (V15~V17 구현본) ─────────────────────────────────
characters 1───∞ character_items   (character_code NULL = 전 캐릭터 공용 variant)
characters 1───∞ character_lines   (character_code NULL = 공용 대사)
item_groups 1───∞ character_items  ★ group(소유 단위) ↔ variant(렌더 단위) 2단 구조
                                     uq_variant UNIQUE NULLS NOT DISTINCT (group_code, character_code)
item_groups 1───∞ missions         (item_group_reward — 미션 보상 아이템, nullable)

users 1───1 user_character_state ∞───1 characters   (selected_character, NULL = 온보딩 미완료)
users 1───∞ user_item_groups ∞───1 item_groups      (소유는 group 단위 → 캐릭터를 바꿔도 옷장 유지)
users 1───∞ user_equipment   ∞───1 user_item_groups (★ 복합 FK (user_id, group_code) → 미소유 착용 DB 차단)
                                                     (slot당 1칸, ROOM_PROP만 slot_index 0~5)
users 1───1 user_progress                            (미션 판정 O(1) 캐시)
users 1───1 user_wallets                             (코인 잔액, CHECK balance >= 0)
users 1───∞ user_missions ∞───1 missions             (달성 이력, PK(user_id, mission_code))
users 1───∞ character_events                         ★ 멱등 관문(uq_character_events_key)
character_events ∞───1 diaries (diary_id, nullable)  (확정 기록 리액션 페이로드)
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
-- [V7__add_emotion_analysis.sql] 감정 코드의 단일 진실원. 6종 시드(멱등 INSERT ... ON CONFLICT DO NOTHING).
-- Phase 7 이후 용도: LLM 분석 결과가 아니라 **사용자가 고르는 프리셋 6종**의 라벨·정렬 마스터.
CREATE TABLE emotion_types (
    code       VARCHAR(20) PRIMARY KEY,        -- JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL
    label_ko   VARCHAR(30) NOT NULL,           -- 기쁨/슬픔/분노/평온/불안/중립
    sort_order INT NOT NULL DEFAULT 0
);

-- ⚠️ themes / tracks / emotion_track_map 은 **구현하지 않는다**(초기 설계에서 폐기).
--   themes(고정 테마 프리셋)  → V7이 diaries 에 색 컬럼을 직접 두는 방식으로 대체 → Phase 7에서 감정 시각 연출 폐기.
--   tracks / emotion_track_map(감정 기반 음악) → MVP 이후 범위, 미구현.

-- ========== 기록 (diaries) ==========
-- [V2__add_diaries.sql] Task 008(기록 CRUD)에서 생성. users(id) FK라 users(V1) 이후 적용.
-- ⚠️ 정정: theme_id/track_id 컬럼은 **끝내 도입되지 않았다**(themes/tracks 테이블 폐기 — 위 참조).
--    본문은 V4에서 리치 텍스트로 전환: content = flutter_quill Delta JSON, content_text = 평문 추출본(검색·미리보기).
CREATE TABLE diaries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    share_token     UUID NOT NULL DEFAULT gen_random_uuid(),    -- 공유 링크용
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,                              -- [V4] 리치 본문(Quill Delta JSON, 사진은 인라인 임베드)
    content_text    TEXT NOT NULL,                              -- [V4·V6] Delta에서 추출한 평문(1~500자 가드 대상)
    written_date    DATE NOT NULL,                              -- 기록 대상 날짜
    visibility      VARCHAR(20) NOT NULL DEFAULT 'PRIVATE',     -- PRIVATE/FRIENDS/PUBLIC (chk_diaries_visibility, V12)
    analysis_status VARCHAR(20) NOT NULL DEFAULT 'DRAFT',       -- DRAFT/PENDING/DONE/FAILED. DRAFT=미확정(수정가능), PENDING=확정·분석대기
    reaction_count  INT NOT NULL DEFAULT 0,                     -- [V14] 공감 수 비정규화 캐시 (CHECK >= 0)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT uq_diaries_share_token UNIQUE (share_token),
    -- 길이 제약은 V4에서 content(Delta JSON — 길이 무의미) → content_text(평문)로 이전됐다.
    -- 1~500: 백엔드 DiaryConstraints.CONTENT_MAX · 앱 maxLength 와 동일 상수.
    CONSTRAINT chk_diaries_content_text_len CHECK (char_length(content_text) BETWEEN 1 AND 500),
    CONSTRAINT chk_diaries_visibility      CHECK (visibility IN ('PRIVATE','FRIENDS','PUBLIC')),          -- V12
    CONSTRAINT chk_diaries_reaction_count  CHECK (reaction_count >= 0)                                     -- V14
);
-- 하루 1기록 제한(수정은 동일 행 UPDATE) — 소프트 삭제분 제외
CREATE UNIQUE INDEX uq_diary_user_day ON diaries(user_id, written_date) WHERE deleted_at IS NULL;
-- 내 기록 목록(최신순)
CREATE INDEX idx_diaries_user_date ON diaries(user_id, written_date DESC) WHERE deleted_at IS NULL;
-- 공개 피드 인덱스 — ⚠️ 정정: 실제 구현(V13)은 커서 정렬키(id DESC)에 맞춘 브랜치별 부분 인덱스를 쓴다
--   (아래 목표안의 (visibility, created_at DESC) 대신). 소셜 섹션(친구/공감 아래)의 V13 주석 참조.
--   idx_diaries_public_feed ON diaries(id DESC) WHERE visibility='PUBLIC' AND deleted_at IS NULL 등.

-- ========== 기록 첨부 사진 — ⚠️ 제거됨 ==========
-- [V3__add_diary_images.sql]로 생성했다가 [V5__drop_diary_images.sql]로 **DROP**했다.
-- 사진은 별도 1:N 테이블이 아니라 **본문 Delta(content)에 인라인 임베드**된다
--   ({"insert":{"image":"/files/diaries/yyyy/MM/{uuid}.jpg"}}).
-- 업로드는 기록 생성과 분리된 POST /diaries/images(파일 → 상대경로 반환)이며, 앱이 그 경로를 Delta에 삽입한다.
-- 따라서 diary_images 테이블·images[] 응답 배열은 **존재하지 않는다**.

-- ========== 감정 분석 결과 — ⚠️ 별도 테이블 없음 (diaries 컬럼으로 인라인) ==========
-- [V7__add_emotion_analysis.sql] emotion_analyses(1:1) 대신 diaries 에 직접 컬럼을 추가했다(조인 제거).
-- 전부 nullable: DRAFT/PENDING 에서는 비어 있고, DONE 시점에 채워진다.
ALTER TABLE diaries
    ADD COLUMN primary_emotion  VARCHAR(20),   -- 대표 감정 코드(emotion_types FK)
    ADD COLUMN background_color VARCHAR(9),    -- 배경색 #RRGGBB(AA)
    ADD COLUMN text_color       VARCHAR(9),    -- 본문 글자색
    ADD COLUMN accent_color     VARCHAR(9),    -- 강조색
    ADD COLUMN ai_comment       VARCHAR(200),  -- AI 한 줄 코멘트
    ADD COLUMN ai_title         VARCHAR(60),   -- AI 생성 제목
    ADD COLUMN mood_emoji       VARCHAR(8),    -- 분위기 이모지
    ADD COLUMN emotion_scores   JSONB,         -- 감정별 점수 분포
    ADD COLUMN analyzed_at      TIMESTAMPTZ;   -- 분석 완료 시각
ALTER TABLE diaries
    ADD CONSTRAINT fk_diaries_emotion FOREIGN KEY (primary_emotion) REFERENCES emotion_types(code);
ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_bg_color
    CHECK (background_color IS NULL OR background_color ~ '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$');
-- (text_color·accent_color 도 동일 형식 CHECK: chk_diaries_text_color / chk_diaries_accent_color)

-- ========== 감정 사용자 직접 입력 (Phase 7 — ✅ V19 적용됨, Task 024) ==========
-- [V19__diary_manual_emotion.sql] **Task 024 구현 완료 — 적용된 스키마다.**
--   (원래 V18 예약이었으나 V18을 보상 재설계(경험치/레벨 드롭)가 선점 → V19로 밀렸다.)
--   LLM 감정 분석은 flag(record.analysis.enabled, 기본 false)로 꺼져 있고, 확정 시 즉시 DONE + 사용자 감정 저장이
--   기본 동작이다. flag를 true로 켜면 기존 V7의 LLM 비동기 분석 경로가 무손상 복구된다.
-- LLM 감정 분석을 flag(record.analysis.enabled)로 끄고 감정을 **사용자가 직접 지정**하는 모델로 전환한다.
--   감정은 순수 기록 메타데이터이며 캐릭터 리액션·미션 판정·해금 어디에도 쓰이지 않는다(달력 점·회고 통계 전용).
--   프리셋 6종 → 기존 diaries.primary_emotion(emotion_types FK) 재사용
--   자유 입력   → 신규 diaries.emotion_label(FK 아님 — 마스터 오염 방지)
--   둘은 배타적이다(동시 지정 시 백엔드 400 EMOTION_CONFLICT). 둘 다 NULL(감정 미입력)도 정상.
ALTER TABLE diaries ADD COLUMN emotion_label VARCHAR(20);   -- 직접 입력 감정(자유 텍스트, ≤20자)

-- 감정을 입력하지 않아도 확정(DONE)할 수 있어야 하므로 V7의 정합 CHECK를 해제한다.
-- (LLM 분석 시절엔 DONE ⇒ primary_emotion NOT NULL 이 불변식이었으나, 이제 감정은 선택 사항이다.)
ALTER TABLE diaries DROP CONSTRAINT IF EXISTS chk_diaries_done_has_emotion;

-- ========== 친구 관계 (V11 구현본) ==========
-- ⚠️ 구현 정정: 컬럼쌍 UNIQUE(requester_id, addressee_id)는 방향 유니크라 A→B / B→A 역방향
--   중복을 막지 못한다. 무방향 정렬쌍 함수 유니크(LEAST/GREATEST)로 {A,B} 쌍당 1행을 강제한다.
--   방향(requester/addressee)은 "누가 신청했나" 의미로 보존, BLOCKED 방향은 blocker_id로 기록.
-- 친구 추가 경로: users.friend_code(혼동문자 제외 base32 8자, UNIQUE) 정확검색 / 닉네임 부분검색.
CREATE TABLE friendships (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requester_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    addressee_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       VARCHAR(20) NOT NULL DEFAULT 'PENDING',        -- PENDING/ACCEPTED/BLOCKED
    blocker_id   BIGINT REFERENCES users(id) ON DELETE CASCADE, -- BLOCKED 시 차단 주체(방향 보존)
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,
    CONSTRAINT chk_no_self_friend     CHECK (requester_id <> addressee_id),
    CONSTRAINT chk_friendship_status  CHECK (status IN ('PENDING','ACCEPTED','BLOCKED')),
    CONSTRAINT chk_friendship_blocker CHECK (status <> 'BLOCKED' OR blocker_id IS NOT NULL)
);
-- 무방향 쌍 유일성(역방향 중복 차단).
CREATE UNIQUE INDEX uq_friendship_pair
    ON friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));
CREATE INDEX idx_friendships_addressee ON friendships(addressee_id, status);
CREATE INDEX idx_friendships_requester ON friendships(requester_id, status);

-- ========== 공감(리액션) — 댓글 없음 (V14 구현본) ==========
-- 공감 수는 읽기(피드) 편향이라 diaries.reaction_count(비정규화 캐시)로 두고, 리액션
-- INSERT/DELETE 와 같은 트랜잭션에서 서비스가 원자 증감(±1)한다. reacted_by_me(뷰어별)는
-- 캐시 불가라 피드 쿼리에서 EXISTS로 산출한다.
CREATE TABLE diary_reactions (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diary_id   BIGINT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type       VARCHAR(20) NOT NULL DEFAULT 'EMPATHY',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_reaction_type CHECK (type IN ('EMPATHY')),
    CONSTRAINT uq_reaction_once  UNIQUE (diary_id, user_id, type)
);
CREATE INDEX idx_diary_reactions_diary ON diary_reactions(diary_id);
-- diaries 확장(V14): reaction_count INT NOT NULL DEFAULT 0 CHECK(>=0).
-- 피드 인덱스(V13, id DESC 커서 정렬 — created_at 아님):
--   idx_diaries_public_feed  ON diaries(id DESC) WHERE visibility='PUBLIC'  AND deleted_at IS NULL;
--   idx_diaries_friends_feed ON diaries(user_id, id DESC) WHERE visibility='FRIENDS' AND deleted_at IS NULL;
-- visibility CHECK(V12): chk_diaries_visibility CHECK (visibility IN ('PRIVATE','FRIENDS','PUBLIC')).
-- users 확장(V11): friend_code VARCHAR(8) UNIQUE NOT NULL(대문자 캐노니컬).

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

-- =====================================================================
-- ========== 캐릭터 카탈로그 (Phase 7 — V15 구현본) ==========
-- [V15__add_character_catalog.sql] 마스터 데이터(캐릭터·아이템·대사). 사용자별 상태는 V17.
-- 핵심: 아이템은 **group(소유·착용·상점 단위) ↔ variant(렌더 단위)** 2단 구조다.
--   캐릭터마다 체형이 달라 옷 PNG를 캐릭터별로 그려야 하지만, 그 사실을 사용자에게 노출하지 않는다.
--   사용자는 "빨간 후드티"(group) 하나를 사고 입을 뿐이고, 렌더 시점에만 내 캐릭터에 맞는 variant를 고른다.
-- 전부 마스터라 변경 빈도가 낮다 → 백엔드 CatalogCache(메모리 스냅샷)가 통째로 캐싱한다.
-- 시드는 ON CONFLICT DO NOTHING(멱등, emotion_types 관례).
-- =====================================================================

-- 캐릭터 마스터. code 가 PK(FK 대상)이며 라벨·에셋 경로는 여기서만 관리한다(2종으로 시작).
CREATE TABLE characters (
    code          VARCHAR(30) PRIMARY KEY,                  -- MONKEY / RED_PANDA (FK 대상)
    name_ko       VARCHAR(30) NOT NULL,                     -- 한국어 표시 이름
    tagline       VARCHAR(100) NOT NULL,                    -- 온보딩 소개 문구(성격 한 줄)
    rive_artboard VARCHAR(50) NOT NULL,                     -- Rive 아트보드명(앱 렌더러가 참조)
    thumbnail_url TEXT NOT NULL,                            -- 앱 로컬 에셋 경로(assets/characters/*.png)
    sort_order    INT NOT NULL DEFAULT 0,                   -- 선택 화면 정렬(작을수록 먼저)
    active        BOOLEAN NOT NULL DEFAULT true,            -- false=신규 선택 불가(기존 선택자는 유지)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ⚠️ thumbnail_url·image_url 은 서버 URL(/files/...)이 **아니라 앱 로컬 에셋 경로**다.
--    캐릭터·아이템 아트는 앱 번들에 동봉되므로 서버는 "어떤 에셋을 그릴지"만 알려준다.
INSERT INTO characters (code, name_ko, tagline, rive_artboard, thumbnail_url, sort_order, active) VALUES
    ('MONKEY',    '원숭이',   '뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.',
     'monkey',    'assets/characters/monkey.png',    0, true),
    ('RED_PANDA', '레서판다', '부지런히 곁을 지켜요. 정 많고 애착이 강한 친구예요.',
     'red_panda', 'assets/characters/red_panda.png', 1, true)
ON CONFLICT (code) DO NOTHING;

-- 아이템 그룹 = 상점·인벤토리·착용이 다루는 **유일한 단위**. 가격·해금 조건도 여기 붙는다.
CREATE TABLE item_groups (
    code          VARCHAR(40) PRIMARY KEY,                  -- OUTFIT_BASIC_TEE 등 (FK 대상)
    slot          VARCHAR(20) NOT NULL,                     -- HAT/OUTFIT/GLASSES/PROP/ROOM_PROP/BACKGROUND
    name_ko       VARCHAR(50) NOT NULL,
    thumbnail_url TEXT NOT NULL,                            -- 상점·옷장 목록용 대표 썸네일(assets/items/*)
    acquire_type  VARCHAR(20) NOT NULL,                     -- DEFAULT(기본 제공)/MISSION(미션 해금)/COIN(구매)
    coin_price    INT NOT NULL DEFAULT 0,                   -- COIN 전용 가격(그 외 0)
    sort_order    INT NOT NULL DEFAULT 0,
    active        BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ⚠️ V21 에서 BOTTOM·SHOES 추가(부위별 착용 확장) → 실제 허용 집합은 8종. user_equipment CHECK 도 동일 확장.
    CONSTRAINT chk_item_groups_slot
        CHECK (slot IN ('HAT','OUTFIT','GLASSES','PROP','ROOM_PROP','BACKGROUND')),
    CONSTRAINT chk_item_groups_acquire
        CHECK (acquire_type IN ('DEFAULT','MISSION','COIN')),
    -- 가격 정합: 구매형이면 양수 가격 필수, 그 외(기본·미션 해금)는 0 고정.
    -- 상점에 "0코인 상품"이나 "가격표 붙은 미션 보상"이 섞이는 걸 DB에서 차단한다.
    CONSTRAINT chk_item_groups_price
        CHECK ((acquire_type = 'COIN' AND coin_price > 0)
            OR (acquire_type <> 'COIN' AND coin_price = 0))
);
-- 상점·옷장 슬롯별 목록 조회(활성 행 한정).
CREATE INDEX idx_item_groups_slot ON item_groups (slot, sort_order) WHERE active;

-- 아이템 variant = **렌더 단위**. 그룹 하나가 캐릭터별 이미지를 여러 개 가진다.
--   character_code NOT NULL → 캐릭터 전용(HAT/OUTFIT/GLASSES/PROP — 체형·머리 크기가 달라 별도 PNG 필요)
--   character_code NULL     → 전 캐릭터 공용(ROOM_PROP/BACKGROUND — 캐릭터 옆·뒤에 놓여 체형 무관)
CREATE TABLE character_items (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_code     VARCHAR(40) NOT NULL REFERENCES item_groups(code) ON DELETE CASCADE,
    character_code VARCHAR(30) REFERENCES characters(code) ON DELETE CASCADE,  -- NULL=공용 variant
    image_url      TEXT NOT NULL,                           -- 앱 로컬 에셋 경로(assets/items/*)
    rive_slot      VARCHAR(20),                             -- Rive VM 이미지 프로퍼티명(hat/outfit/.../roomProp0..5)
    render_meta    JSONB,                                   -- 플레이스홀더 렌더러(Task 029) 전용
                                                            -- {"anchorX":0.5,"anchorY":0.18,"scale":0.42,"z":30}
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ★ (group, 캐릭터) 당 variant 1행. 일반 UNIQUE 는 NULL 을 서로 '구별되는 값'으로 취급해
    --   공용 variant(character_code IS NULL)의 중복 행을 막지 못한다. PG15+ 의 NULLS NOT DISTINCT 로
    --   NULL 도 같은 값으로 보게 해 "공용 variant 도 group 당 정확히 1행"을 제약 하나로 강제한다(운영 PG18).
    --   대안(부분 유니크 인덱스 2개: character_code IS NULL / IS NOT NULL)보다 단순하다.
    CONSTRAINT uq_variant UNIQUE NULLS NOT DISTINCT (group_code, character_code)
);
-- variant 해석 경로: (선택 캐릭터 + 공용) 을 한 번에 긁는 조회.
CREATE INDEX idx_character_items_character ON character_items (character_code, group_code);

-- 캐릭터 대사. **감정이 아니라 맥락(context)** 기반이다(감정은 캐릭터와 완전 분리).
--   원숭이는 느긋한 말투, 레서판다는 애쓰는 말투 — 캐릭터별 대사로 성격 대비를 만든다.
--   character_code NULL = 공용 대사(캐릭터 미선택·폴백 시 사용).
CREATE TABLE character_lines (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    character_code VARCHAR(30) REFERENCES characters(code) ON DELETE CASCADE,  -- NULL=공용 대사
    context        VARCHAR(20) NOT NULL,                    -- CONFIRM/STREAK_3/STREAK_7/MISSION/LEVEL_UP/IDLE
    line_ko        VARCHAR(120) NOT NULL,                   -- 대사 본문(리액션 payload 에 실려 앱이 표시)
    rive_trigger   VARCHAR(40),                             -- 함께 재생할 Rive 트리거명(NULL=기본 모션)
    weight         INT NOT NULL DEFAULT 1,                  -- 가중 랜덤 선택(클수록 자주 뽑힘)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ⚠️ 'LEVEL_UP' 맥락은 레벨 제거(V18)로 **미사용(inert)**이나 enum·대사 시드는 유지한다
    --    (컬럼이 아닌 CHECK enum이라 앞으로 생성되지 않아 무해). Task 028에서 이벤트 분류와 함께 정리 예정.
    CONSTRAINT chk_character_lines_context
        CHECK (context IN ('CONFIRM','STREAK_3','STREAK_7','MISSION','LEVEL_UP','IDLE')),
    CONSTRAINT chk_character_lines_weight CHECK (weight > 0)
);
-- 대사 선택(Task 028 LineService): (캐릭터, 맥락) 등치 조회 + 공용 폴백.
CREATE INDEX idx_character_lines_ctx ON character_lines (context, character_code);

-- 대사 시드 33행: 원숭이 13 + 레서판다 13 + 공용(NULL) 7. 맥락 6종을 모두 덮는다.
--   예) ('MONKEY','CONFIRM','오늘도 한 줄 남겼네. 천천히 해도 다 남더라.','nod',2)
--       ('RED_PANDA','CONFIRM','오늘 것도 잘 챙겼어! 하나도 안 흘렸어.','nod',2)
--       (NULL,'CONFIRM','오늘의 기록이 저장됐어요.',NULL,1)
--   rive_trigger 시드값: nod/relax/clap/cheer/hug/levelup (NULL=기본 모션)

-- ⚠️ [V21__replace_item_catalog.sql] 이 아래 V15 시드 5종을 **전부 교체**했다. 현재 카탈로그는
--   부위별 착용 5종(전부 COIN·구매 대상, 슬롯 HAT/GLASSES/OUTFIT/BOTTOM/SHOES)이다:
--     HAT_CAP_BLACK(15) · GLASSES_ROUND(15) · OUTFIT_LOVE_HOOD(50) · BOTTOM_CARGO_SAND(50) · SHOES_MAX95(20)
--   DEFAULT/MISSION 아이템은 없다(신규 유저는 빈 옷장=전부 잠금). 미션(DIARY_10·STREAK_7)의
--   item_group_reward 는 V21 에서 NULL 로 정리됐다. 아래 V15 원본은 설계 이력으로만 남긴다.
-- 아이템 시드 5종(group). MISSION 그룹은 V16 missions.item_group_reward 가 참조한다.
INSERT INTO item_groups (code, slot, name_ko, thumbnail_url, acquire_type, coin_price, sort_order) VALUES
    ('OUTFIT_BASIC_TEE', 'OUTFIT',     '기본 흰 티셔츠', 'assets/items/outfit_basic_tee.png', 'DEFAULT',   0,  0),
    ('ROOM_PROP_PLANT',  'ROOM_PROP',  '작은 화분',      'assets/items/room_prop_plant.png',  'DEFAULT',   0, 10),
    ('HAT_PARTY',        'HAT',        '파티 모자',      'assets/items/hat_party.png',        'MISSION',   0, 20),
    ('BG_COZY_ROOM',     'BACKGROUND', '아늑한 방',      'assets/items/bg_cozy_room.png',     'MISSION',   0, 30),
    ('HAT_STRAW',        'HAT',        '밀짚모자',       'assets/items/hat_straw.png',        'COIN',    120, 40)
ON CONFLICT (code) DO NOTHING;

-- variant 시드 8행: 착용 아이템(OUTFIT/HAT 3종)은 캐릭터별 2행씩(체형 차이 → 별도 PNG),
--   방 소품·배경(ROOM_PROP/BACKGROUND 2종)은 공용 1행씩(character_code NULL).
--   레서판다는 통통한 체형·큰 머리라 같은 옷·모자라도 render_meta 의 scale·anchorY 를 보정한다.
INSERT INTO character_items (group_code, character_code, image_url, rive_slot, render_meta) VALUES
    ('OUTFIT_BASIC_TEE', 'MONKEY',    'assets/items/outfit_basic_tee_monkey.png',    'outfit',
     '{"anchorX":0.5,"anchorY":0.55,"scale":0.60,"z":30}'),
    ('OUTFIT_BASIC_TEE', 'RED_PANDA', 'assets/items/outfit_basic_tee_red_panda.png', 'outfit',
     '{"anchorX":0.5,"anchorY":0.58,"scale":0.66,"z":30}'),
    -- HAT_PARTY·HAT_STRAW 도 동일하게 캐릭터별 2행(z:40, 머리 크기에 따라 scale 보정)
    ('ROOM_PROP_PLANT',  NULL,        'assets/items/room_prop_plant.png',            'roomProp0',
     '{"anchorX":0.82,"anchorY":0.78,"scale":0.30,"z":10}'),
    ('BG_COZY_ROOM',     NULL,        'assets/items/bg_cozy_room.png',               'background',
     '{"anchorX":0.5,"anchorY":0.5,"scale":1.0,"z":0}');

-- ========== 미션(업적) — 유일한 해금 경로 (Phase 7 — V16 구현본) ==========
-- [V16__add_missions.sql] 해금 규칙을 한 테이블에 모은다. 판정은 서비스(MissionEvaluator)가 수행하고
--   DB 트리거는 쓰지 않는다(작심삼일 상태 전이와 동일 방침).
-- rule(JSONB)의 임계값 **키는 타입마다 다르다**(count/days/seq). 매퍼가 COALESCE 로
--   threshold 하나로 정규화해 읽으므로 서비스·앱은 타입별 키를 알 필요가 없다.
CREATE TABLE missions (
    code              VARCHAR(40) PRIMARY KEY,              -- DIARY_10 등 (event_key 'MISSION:{code}' 에 사용)
    title             VARCHAR(60) NOT NULL,
    description       VARCHAR(200) NOT NULL,
    rule              JSONB NOT NULL,                       -- 판정 규칙(5종). MissionEvaluator 가 해석
    coin_reward       INT NOT NULL DEFAULT 0,               -- 코인 보상(0 = 없음)
    item_group_reward VARCHAR(40) REFERENCES item_groups(code),  -- 아이템 해금 보상(group 단위, NULL=없음)
    sort_order        INT NOT NULL DEFAULT 0,
    active            BOOLEAN NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_missions_coin CHECK (coin_reward >= 0),
    -- 보상 없는 미션은 무의미 → 코인이든 아이템이든 최소 하나는 있어야 한다.
    CONSTRAINT chk_missions_reward
        CHECK (coin_reward > 0 OR item_group_reward IS NOT NULL),
    -- rule 타입 오타 방어(★ 감정 규칙은 의도적으로 없음). 타입 추가 시 이 집합만 넓힌다.
    --   ⚠️ V16에는 'LEVEL'도 있었으나 **V18(보상 재설계)에서 CHECK를 4종으로 재정의**하며 제거됐다
    --      (경험치/레벨 개념 폐기). 아래는 V18 이후의 최종 형태다.
    CONSTRAINT chk_missions_rule_type
        CHECK (rule ->> 'type' IN
               ('DIARY_COUNT','CONSECUTIVE_DAYS','RESOLUTION_SUCCESS','RESOLUTION_STREAK'))
);
-- 미션 목록(활성 행 한정, 정렬 순).
CREATE INDEX idx_missions_active ON missions (sort_order) WHERE active;

-- 달성 이력(달성은 되돌리지 않으므로 갱신·삭제 없음). PK가 곧 "미션당 1회 달성" 보장.
-- 보상 중복 지급 방지는 character_events 멱등 관문이, 이력 중복은 이 PK 가 담당한다(이중 방어).
CREATE TABLE user_missions (
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mission_code VARCHAR(40) NOT NULL REFERENCES missions(code) ON DELETE CASCADE,
    achieved_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, mission_code)
);

-- 초기 미션 시드 4종: 기록 습관(DIARY_COUNT/CONSECUTIVE_DAYS) + 작심삼일(RESOLUTION_*).
--   ⚠️ V16에는 성장 미션 'LEVEL_5'(LEVEL 규칙)가 있었으나 **V18(보상 재설계)에서 제거**됐다
--      (경험치/레벨 폐기). 아래는 V18 이후의 최종 4종이다.
-- 아이템 보상은 V15 의 MISSION 그룹(HAT_PARTY·BG_COZY_ROOM)을 해금한다.
INSERT INTO missions (code, title, description, rule, coin_reward, item_group_reward, sort_order) VALUES
    ('DIARY_10',      '기록 10개',       '기록을 10개 확정하면 파티 모자를 드려요.',
     '{"type":"DIARY_COUNT","count":10}',        50, 'HAT_PARTY',     10),
    ('STREAK_7',      '7일 연속 기록',   '7일 연속으로 기록을 확정해 보세요.',
     '{"type":"CONSECUTIVE_DAYS","days":7}',    100, 'BG_COZY_ROOM',  20),
    ('RESOL_1',       '첫 작심삼일 완주', '작심삼일을 처음으로 완주해 보세요.',
     '{"type":"RESOLUTION_SUCCESS","count":1}',  30, NULL,            30),
    ('RESOL_STREAK_3','3연속 작심삼일',  '같은 결심을 3번 연속(9일) 이어가 보세요.',
     '{"type":"RESOLUTION_STREAK","seq":3}',    150, NULL,            40)
ON CONFLICT (code) DO NOTHING;

-- ========== 사용자 캐릭터 상태 (Phase 7 — V17 구현본) ==========
-- [V17__add_user_character_state.sql] 선택·소유·착용·진척도·지갑·이벤트. 전부 users(id) FK CASCADE.
--   상태 행(state/wallet/progress)은 캐릭터 도메인 최초 접근 시 서비스가 JIT 생성하며
--   (ON CONFLICT DO NOTHING → 멱등), 소프트 삭제 컬럼을 두지 않는다(탈퇴 = 물리 CASCADE 회수).
--   DB 트리거는 쓰지 않는다.

-- 선택 캐릭터만 보관. user_id 가 PK(1:1).
--   ⚠️ V17에는 성장 컬럼 level(DEFAULT 1)·exp(DEFAULT 0)와 chk_user_character_level/exp CHECK가 있었으나
--      **V18(보상 재설계)에서 전부 드롭**됐다 — 경험치/레벨 개념 폐기, 성장은 코인·미션 해금으로만 표현.
--      아래는 V18 이후의 최종 형태다.
CREATE TABLE user_character_state (
    user_id            BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    selected_character VARCHAR(30) REFERENCES characters(code),  -- NULL=온보딩 미완료(미선택)
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 소유는 **group 단위**. 캐릭터를 바꿔도 옷장이 그대로 따라온다(variant 재해석만 일어난다).
-- 획득 경로(source) 컬럼은 두지 않는다 — 획득 이력은 character_events(원장)가 갖는다.
CREATE TABLE user_item_groups (
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_code  VARCHAR(40) NOT NULL REFERENCES item_groups(code) ON DELETE CASCADE,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, group_code)
);

-- 착용도 **group 단위**. 단일 슬롯은 1칸(slot_index=0), ROOM_PROP만 0~5 다중 진열(Rive roomProp0..5 와 1:1).
-- slot 과 item_groups.slot 의 일치(HAT 칸에 OUTFIT group)는 DB 로 못 막으므로 서비스가 검증한다
--   (Task 027: 400 ITEM_SLOT_MISMATCH).
CREATE TABLE user_equipment (
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    slot        VARCHAR(20) NOT NULL,
    slot_index  SMALLINT NOT NULL DEFAULT 0,               -- 단일 슬롯=0 고정, ROOM_PROP=0..5
    group_code  VARCHAR(40) NOT NULL,
    equipped_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, slot, slot_index),
    CONSTRAINT chk_user_equipment_slot
        CHECK (slot IN ('HAT','OUTFIT','GLASSES','PROP','ROOM_PROP','BACKGROUND')),
    CONSTRAINT chk_user_equipment_slot_index_range CHECK (slot_index BETWEEN 0 AND 5),
    -- ★ ROOM_PROP 이 아니면 칸은 0번 하나뿐 → 단일 슬롯 중복 착용을 물리적으로 차단.
    CONSTRAINT chk_user_equipment_slot_index
        CHECK (slot = 'ROOM_PROP' OR slot_index = 0),
    -- 같은 아이템을 두 칸에 겹쳐 진열 금지(예: 화분 하나를 roomProp0·1 동시 배치).
    CONSTRAINT uq_user_equipment_group UNIQUE (user_id, group_code),
    -- ★ 소유하지 않은 group 착용 불가(최종 방어선. 서비스는 409 ITEM_NOT_OWNED 로 먼저 거른다).
    --   item_groups(code) 가 아니라 **user_item_groups(user_id, group_code) 복합 FK** 를 참조한다.
    CONSTRAINT fk_user_equipment_owned
        FOREIGN KEY (user_id, group_code)
        REFERENCES user_item_groups (user_id, group_code) ON DELETE CASCADE
);

-- 미션 판정 O(1) 캐시. 매 판정마다 diaries/resolutions 를 COUNT 집계하지 않기 위한 비정규화 테이블.
-- 보상 엔진(Task 028)이 멱등 게이트 통과 후 같은 트랜잭션에서 UPSERT + RETURNING 으로 갱신하고
--   그 반환값으로 미션을 판정한다.
CREATE TABLE user_progress (
    user_id                  BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    confirmed_diary_count    INT NOT NULL DEFAULT 0,       -- 확정(DONE) 기록 누적 수 → DIARY_COUNT
    consecutive_days         INT NOT NULL DEFAULT 0,       -- 현재 연속 확정일 → CONSECUTIVE_DAYS
    last_confirmed_date      DATE,                         -- 연속일 계산 기준(같은 날 재확정=불변)
    resolution_success_count INT NOT NULL DEFAULT 0,       -- 작심삼일 완주 누적 → RESOLUTION_SUCCESS
    max_streak_seq           SMALLINT NOT NULL DEFAULT 0,  -- 최대 연장 순번(V9 resolutions.streak_seq) → RESOLUTION_STREAK
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_user_progress_counts
        CHECK (confirmed_diary_count >= 0 AND consecutive_days >= 0
           AND resolution_success_count >= 0 AND max_streak_seq >= 0)
);

-- 코인 지갑. 잔액 음수는 CHECK 가 최종 방어하고, 소비는 서비스가
--   UPDATE user_wallets SET balance = balance - ? WHERE user_id = ? AND balance >= ?
-- 로 수행해 0행이면 COIN_INSUFFICIENT 로 거절한다(경합 안전).
CREATE TABLE user_wallets (
    user_id    BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    balance    INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_user_wallets_balance CHECK (balance >= 0)
);

-- ★ 캐릭터 이벤트 — 이 한 테이블이 네 가지 역할을 겸한다.
--   ① 멱등 관문: uq_character_events_key(user_id, event_key). INSERT ... ON CONFLICT DO NOTHING 이
--      1행을 반환할 때만 모든 부작용(코인·진척도·미션·해금)이 실행된다. 재전달·폴러 중복은 0행 → no-op.
--   ② 코인 원장: coin_delta(적립 +, 구매 -, 아이템만 해금 0) / balance_after(그 시점 잔액 스냅샷).
--   ③ 리액션 페이로드: payload(대사·획득 아이템·미션)가 앱 리액션 화면의 단일 소스(폴링 불필요).
--   ④ 보상 알림함: acked_at IS NULL = 미확인 보상 → 홈 상단 뱃지, 확인 처리 API 로 ack.
-- event_key 규약(Task 028): 'DIARY_CONFIRM:{diaryId}' / 'RESOLUTION_SUCCESS:{resolutionId}'
--                           / 'MISSION:{missionCode}' / 'PURCHASE:{groupCode}' / 'LEVEL_UP:{level}'
--   ⚠️ 'LEVEL_UP' 계열(event_type·event_key)은 레벨 제거(V18)로 **미사용(inert)**이나 enum은 유지한다.
--      Task 028에서 이벤트 분류를 확정하며 함께 정리 예정(지금 CHECK 재정의는 실익 없음).
CREATE TABLE character_events (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_key     TEXT NOT NULL,                           -- ★ 사용자 내 유일(멱등 키)
    event_type    VARCHAR(30) NOT NULL,                    -- DIARY_CONFIRM/RESOLUTION_SUCCESS/MISSION/PURCHASE/LEVEL_UP
    coin_delta    INT NOT NULL DEFAULT 0,
    balance_after INT,                                     -- 코인 변동 없는 이벤트는 NULL 가능
    diary_id      BIGINT REFERENCES diaries(id) ON DELETE SET NULL,  -- 확정 리액션 조회 키(그 외 NULL)
    payload       JSONB,
    acked_at      TIMESTAMPTZ,                             -- 사용자가 리액션·보상함을 확인한 시각
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ★ 멱등 관문의 물리적 근거: 같은 사용자·같은 사건은 단 한 번만 기록·보상된다.
    CONSTRAINT uq_character_events_key UNIQUE (user_id, event_key),
    CONSTRAINT chk_character_events_type
        CHECK (event_type IN
               ('DIARY_CONFIRM','RESOLUTION_SUCCESS','MISSION','PURCHASE','LEVEL_UP')),
    CONSTRAINT chk_character_events_balance CHECK (balance_after IS NULL OR balance_after >= 0)
);
-- 미확인 보상함(뱃지 카운트·커서 목록): 미확인 행만 얇게 인덱싱.
CREATE INDEX idx_character_events_unacked
    ON character_events (user_id, id DESC) WHERE acked_at IS NULL;
-- 확정 직후 리액션 조회(GET /characters/me/reaction?diaryId=).
CREATE INDEX idx_character_events_diary
    ON character_events (user_id, diary_id) WHERE diary_id IS NOT NULL;

-- ⚠️ V17 까지가 **스키마 구현본**이다. character_events 에 실제로 행을 쓰는 주체(보상 엔진 — 코인 적립·
--    구매·미션 지급·리액션)는 **Task 028 미구현**이라, 현재 이 테이블은 비어 있고 API 의
--    coinBalance/unackedRewardCount 는 항상 0 이다. 테이블·제약은 Task 027 단계에서 이미 확정해 뒀다.
```

## 5. 주요 설계 결정

- **DB는 별도 PostgreSQL(Supabase 미사용)**: 앱 데이터는 Supabase와 무관한 별도 PostgreSQL에 저장한다(로컬: Docker, 배포: 관리형/자체호스팅). Supabase는 **Auth 전용**이며, 인증↔데이터는 `users.supabase_uid` 컬럼 매핑으로만 연결한다(`auth.users` FK·RLS·트리거 미사용 — 물리적으로 다른 DB).
- **Supabase Auth 매핑**: 소셜 로그인·세션(access/refresh)은 Supabase Auth가 관리하고, 백엔드는 `users.supabase_uid`(= Supabase `auth.users.id`, JWT `sub`)로 1:1 매핑한다. 별도 `social_accounts`/`refresh_tokens` 테이블을 두지 않으며, 최초 인증 요청 시 `users` 행을 자동 생성(JIT 프로비저닝)한다. `users.uuid`(외부 공유 노출용)와 `supabase_uid`(인증 매핑용)는 용도가 다른 별개 식별자다.
- **하루 1기록 + draft→확정 라이프사이클**: `uq_diary_user_day` 부분 유니크 인덱스로 사용자·날짜당 1행 강제. 동일 날짜 재작성은 신규 INSERT가 아닌 **UPDATE**로 처리한다. `analysis_status`가 `DRAFT`인 기록만 수정 가능하며, '오늘을 기억하기'로 **확정(`PENDING`)하면 감정 분석을 1회 수행**한다. **확정 후에는 수정 불가**(재upsert·PUT 모두 409 `DIARY_ALREADY_CONFIRMED`)이며, **삭제는 허용**한다(소프트 삭제 → 같은 날짜 재작성 가능). 매 수정마다 LLM을 호출하던 과부하를 피하기 위해 분석을 확정 시점 1회로 한정한다.
- **감정 분석 결과는 `diaries` 컬럼으로 인라인(V7)**: `emotion_analyses`(1:1) 테이블을 두지 않고 `diaries`에 감정·색·AI 필드를 직접 넣었다. 일기 상세·피드가 항상 감정과 함께 읽히므로 1:1 조인은 비용만 늘린다. `themes`/`tracks` 프리셋 테이블은 **도입하지 않았다**(고정 테마 매핑 대신 일기별 자유 생성 → 이후 Phase 7에서 감정 시각 연출 자체를 폐기).
- **감정은 사용자 입력 + 순수 메타데이터(V18 예약 — ⚠️ Task 024 미착수)**: 아래는 **아직 적용되지 않은 목표 설계**다. 현재 스키마·백엔드는 **V7의 LLM 비동기 감정 분석이 그대로 활성**이며(확정 시 1회 분석 → `DONE`), `emotion_label` 컬럼도 없다. (목표) LLM 감정 분석을 `record.analysis.enabled` flag로 끄고(코드·컬럼은 보존 — 되살릴 수 있게), 감정은 **사용자가 프리셋 6종(`primary_emotion` FK) 중 택1 또는 자유 텍스트(`emotion_label`, ≤20자)로 직접 입력**한다. 자유 입력을 FK가 아닌 별도 컬럼으로 둔 이유는 `emotion_types` 마스터를 사용자 입력으로 오염시키지 않기 위해서다. **둘은 배타적**(동시 지정 시 400 `EMOTION_CONFLICT`)이고 **둘 다 NULL(감정 미입력)도 확정 가능**하다 — 그래서 V7의 `chk_diaries_done_has_emotion`(DONE ⇒ 감정 필수)을 DROP했다. 감정은 **캘린더 점 색·월간 회고 통계 전용**이며 캐릭터 리액션·미션 판정·해금 어디에도 관여하지 않는다.
- **★ 아이템의 group ↔ variant 2단 구조**: 캐릭터마다 체형이 다르므로(레서판다가 통통하고 팔이 짧다) **옷 PNG는 캐릭터별로 따로 그려야 한다**. 그러나 이 제작상의 사실을 사용자 모델에 노출하면 "원숭이용 후드티"와 "레서판다용 후드티"를 따로 사야 하는 이상한 상점이 된다. 그래서 **소유(`user_item_groups`)·착용(`user_equipment`)·구매·미션 보상은 전부 `group_code` 단위**로 하고, **렌더할 때만** `(group_code, character_code)`로 `character_items`를 조회해 variant 이미지를 고른다. 결과적으로 **캐릭터를 바꿔도 옷장·착용 상태가 그대로 유지**되고 variant만 재해석된다(`PUT /characters/me/selection`은 `user_equipment`를 손대지 않는다). `ROOM_PROP`/`BACKGROUND`는 캐릭터 옆·뒤에 놓여 체형과 무관하므로 `character_code IS NULL`(공용) variant 하나로 끝난다. **해석 규칙은 "캐릭터 전용 우선 → 없으면 공용 폴백 → 그것도 없으면 미해석"**이며, 조회 경로는 SQL(`DISTINCT ON` + `ORDER BY character_code NULLS LAST`)과 메모리 캐시(`CatalogCache.resolveVariant`)가 같은 규칙을 쓴다.
- **`uq_variant`는 `UNIQUE NULLS NOT DISTINCT (group_code, character_code)`**: 일반 UNIQUE는 NULL을 서로 '구별되는 값'으로 취급해 **공용 variant(`character_code IS NULL`)의 중복 행을 막지 못한다**. PostgreSQL 15+의 `NULLS NOT DISTINCT`로 NULL도 같은 값으로 보게 해 "공용 variant도 group당 정확히 1행"을 **제약 하나로** 강제했다(운영 PG18). 부분 유니크 인덱스 2개(`character_code IS NULL` / `IS NOT NULL`)로 나눠 거는 대안보다 단순하고, variant 후보가 최대 2행(전용+공용)임이 제약으로 보장되므로 해석 로직이 단순해진다.
- **미소유 착용은 복합 FK가 DB에서 차단**: `user_equipment`는 `item_groups(code)`가 아니라 **`user_item_groups(user_id, group_code)`를 복합 FK로 참조**한다(`fk_user_equipment_owned`). "존재하는 아이템"이 아니라 "**내가 가진 아이템**"만 착용 가능하다는 규칙이 애플리케이션 검증이 아니라 스키마의 성질이 된다. 서비스는 그 앞에서 먼저 409 `ITEM_NOT_OWNED`로 거르고, FK는 최종 방어선이다. 슬롯 칸 수는 CHECK로 강제한다(`chk_user_equipment_slot_index`: `ROOM_PROP`이 아니면 `slot_index=0` 한 칸뿐 → 단일 슬롯 중복 착용 불가, `ROOM_PROP`만 0~5). 다만 **`slot`과 `item_groups.slot`의 일치(HAT 칸에 OUTFIT 그룹)는 DB로 막을 수 없어** 서비스가 검증한다(400 `ITEM_SLOT_MISMATCH`). 대신 **캐릭터를 추가하면 기존 모든 옷의 variant를 새로 그려야 하므로**(에셋 곱셈) 캐릭터 추가는 아이템이 적을 때 신중히 한다. 내 캐릭터용 variant가 아직 없는 그룹을 착용하려 하면 409 `ITEM_VARIANT_MISSING`.
- **★ 멱등 관문 — `character_events(user_id, event_key) UNIQUE`**: 보상 시스템 전체가 이 제약 하나에 걸린다. 이 테이블은 ① **멱등 게이트** ② **코인 원장**(`coin_delta`/`balance_after`) ③ **리액션 페이로드**(`payload` — 대사·달성 미션·잔액) ④ **미확인 보상 알림함**(`acked_at IS NULL`)을 겸한다. 보상 엔진은 `INSERT ... ON CONFLICT DO NOTHING`으로 게이트를 먼저 꽂고, **1행이 들어간 경우에만** 코인 적립·진척도 갱신·미션 판정·해금을 실행한다(0행이면 즉시 return). 즉 **게이트 INSERT 성공이 모든 부작용의 유일한 진입 조건**이다. 덕분에 `@TransactionalEventListener(AFTER_COMMIT)`의 재전달, 백스톱 폴러의 중복 스캔, 앱의 재시도가 몇 번 겹쳐도 잔액·진척도는 절대 이중 반영되지 않는다. `event_key`는 사건의 자연키(`DIARY_CONFIRM:{diaryId}` / `RESOLUTION_SUCCESS:{resolutionId}` / `MISSION:{missionCode}` / `PURCHASE:{groupCode}` / `LEVEL_UP:{level}`)로 만든다. ⚠️ **테이블·제약은 V17로 구현됐지만 여기에 행을 쓰는 보상 엔진은 Task 028 미구현**이라, 현재 `character_events`는 비어 있다.
- **미션 판정은 서비스에서, `user_progress`는 O(1) 캐시**: 해금 규칙은 `missions.rule`(JSONB) 한 곳에 모으고, 판정은 `MissionEvaluator` **순수 함수**가 수행한다(작심삼일과 동일하게 **DB 트리거 미사용** 원칙 유지 — 상태 전이는 항상 서비스/배치). 매 확정마다 `diaries`/`resolutions`를 COUNT 집계하면 기록이 쌓일수록 확정이 느려지므로, 판정 입력은 `user_progress`(확정 수·연속일·완주 수·최대 streak)에서 **O(1)로 읽는다**. 진척도는 멱등 게이트 통과 후 같은 트랜잭션에서 UPSERT + RETURNING으로 갱신하며 반환값이 곧 판정 입력이 된다.
- **미션 rule JSONB 스키마**(감정 규칙은 **없다** — 감정은 해금과 완전 분리). ⚠️ **임계값 키는 타입마다 다르다**(`threshold` 단일 키가 아니다). 매퍼가 `COALESCE(rule->>'count', rule->>'days', rule->>'seq')::int`로 **`threshold` 하나로 정규화해** 읽으므로, 서비스·앱·API 응답은 `(type, threshold)` 두 값만 본다. 타입 오타는 `chk_missions_rule_type` CHECK가 막는다(⚠️ V16의 `LEVEL` 규칙은 **V18 보상 재설계에서 제거** — 아래 4종이 최종):

  | `type` | rule 임계값 키 | 의미 | 판정 입력(`user_progress`) |
  |---|---|---|---|
  | `DIARY_COUNT` | `count` | 확정 기록 누적 N건 | `confirmed_diary_count` |
  | `CONSECUTIVE_DAYS` | `days` | 연속 기록 N일 | `consecutive_days` |
  | `RESOLUTION_SUCCESS` | `count` | 작심삼일 완주 N회 | `resolution_success_count` |
  | `RESOLUTION_STREAK` | `seq` | 연장 체인 N연속 | `max_streak_seq` (`resolutions.streak_seq` 재사용) |

  ```jsonc
  {"type":"DIARY_COUNT","count":10}       // DIARY_10       — 확정 기록 10건 (+50코인, HAT_PARTY 해금)
  {"type":"CONSECUTIVE_DAYS","days":7}    // STREAK_7       — 7일 연속 기록 (+100코인, BG_COZY_ROOM 해금)
  {"type":"RESOLUTION_SUCCESS","count":1} // RESOL_1        — 작심삼일 첫 완주 (+30코인)
  {"type":"RESOLUTION_STREAK","seq":3}    // RESOL_STREAK_3 — 3연속 연장 (+150코인)
  ```
  달성은 되돌리지 않으므로 `user_missions`는 PK `(user_id, mission_code)`만 두고 갱신·삭제하지 않는다. 보상 지급도 `character_events`의 `MISSION:{code}` 게이트를 통과하므로 임계값을 여러 번 넘겨도 **1회만** 지급된다.
- **코인 음수 방지(경합 안전)**: 소비는 `UPDATE user_wallets SET balance = balance - ? WHERE user_id = ? AND balance >= ?` 한 문장으로 하고, **0행이면 409 `COIN_INSUFFICIENT`**로 거절한다(SELECT 후 UPDATE의 TOCTOU를 원천 제거). `chk_user_wallets_balance CHECK (balance >= 0)`는 그 위의 **최종 방어선**이며, 여기에 걸리는 것은 서비스 버그를 뜻한다. 적립은 항상 수행하고(`record.character.coin-enabled`와 무관), 상점 **소비만** flag로 게이팅한다(off면 403 `FEATURE_DISABLED`).
- **캐릭터 상태의 JIT 프로비저닝**: `user_character_state`/`user_progress`/`user_wallets` 3행 + **기본 지급(`acquire_type='DEFAULT'`) 아이템 소유(`user_item_groups`)**를 캐릭터 도메인 **모든 진입점(조회 포함)**에서 `INSERT ... ON CONFLICT DO NOTHING`으로 만든다(멱등 — 동시 최초요청 2건에도 각 1행). `users`의 JIT 프로비저닝과 같은 철학이며, DB 트리거는 쓰지 않는다. 기본 지급은 `INSERT ... SELECT ... WHERE acquire_type='DEFAULT' AND active`라 그룹이 늘어도 코드가 바뀌지 않는다. `selected_character`가 NULL이면 온보딩 미완료 → 앱이 캐릭터 선택 화면으로 분기한다(**404가 아니라 200 + `character: null`**).
- **카탈로그는 메모리 캐시**: `characters`/`item_groups`/`character_items`/`missions`는 전부 마스터(변경 빈도 ~0)라 매 요청 SQL을 태우지 않는다. `CatalogCache`가 최초 접근 시 1회 적재해 **불변 스냅샷을 volatile 참조로 통째 교체**하고(읽기 경로 무락), `render_meta`(JSONB) 파싱도 적재 시 1회만 수행한다. 시드 변경 후에는 `reload()`로 재기동 없이 갱신한다.
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
  - `V2__add_diaries.sql` — `diaries` (Task 008, 기록 CRUD). `chk_diaries_content_len`(1~500) 포함. **`theme_id`/`track_id`는 이후로도 추가되지 않았다**(themes/tracks 폐기).
  - `V3__add_diary_images.sql` — `diary_images` (Task 008, 사진 첨부 1:N) — **V5에서 DROP됨**
  - `V4__diary_rich_content.sql` — 리치 본문 전환(`content` = Quill Delta JSON, `content_text` 신설 + 길이 CHECK 이전)
  - `V5__drop_diary_images.sql` — `diary_images` **DROP**(사진을 본문 Delta에 인라인 임베드)
  - `V6__diary_content_text_not_null.sql` — `content_text` NOT NULL 강화
  - `V7__add_emotion_analysis.sql` — `emotion_types`(6종 시드) + **`diaries`에 감정·색·AI 컬럼 직접 추가**(`emotion_analyses` 1:1 테이블은 만들지 않음)
  - `V8__diary_draft_lifecycle.sql` — `diaries.analysis_status` 기본값을 `'PENDING'` → **`'DRAFT'`**로 변경하고 `CHECK (analysis_status IN ('DRAFT','PENDING','DONE','FAILED'))` 제약 추가(기록 draft→확정 라이프사이클). 기존 데이터 백필 없음.
  - `V9__add_resolutions.sql` — `resolutions` + `resolution_checks` (작심삼일 3일 결심 + 일별 체크 한 세트)
  - `V10__add_device_tokens.sql` — `device_tokens` (FCM 서버 푸시 기기 토큰)
  - **소셜(Phase 6) 실제 적용본**: `V11`(users.friend_code + friendships), `V12`(diaries.visibility CHECK), `V13`(피드 부분 인덱스, id DESC), `V14`(diary_reactions + diaries.reaction_count). friendships는 무방향 정렬쌍 유니크 + blocker_id로 목표 DDL을 정정했다(위 소셜 섹션 참조).
  - **캐릭터 도메인(Phase 7) 실제 적용본 — `V15`~`V17`**(Task 026 구현):
    - `V15__add_character_catalog.sql` — `characters`(2종 시드: `MONKEY`·`RED_PANDA`) + `item_groups`(소유·착용·상점 단위, 5종 시드) + `character_items`(렌더 variant 8행, **`uq_variant UNIQUE NULLS NOT DISTINCT (group_code, character_code)`**) + `character_lines`(맥락별 대사 33행)
    - `V16__add_missions.sql` — `missions`(`rule` JSONB + `chk_missions_rule_type`·`chk_missions_reward`, 5종 시드) + `user_missions`(달성 이력, PK `(user_id, mission_code)`)
    - `V17__add_user_character_state.sql` — `user_character_state`, `user_item_groups`, `user_equipment`(**복합 FK → `user_item_groups`**), `user_progress`, `user_wallets`, `character_events`(**`uq_character_events_key(user_id, event_key)`** — 멱등 관문)
    - **`V18__drop_level_exp.sql`(적용됨 — 2026-07-15 보상 재설계 1단계)** — 경험치/레벨 개념 폐기: `user_character_state`의 `level`/`exp` 컬럼과 `chk_user_character_level`/`chk_user_character_exp` CHECK 드롭, `missions`의 `LEVEL_5` 시드 삭제 + `chk_missions_rule_type` CHECK를 4종(`DIARY_COUNT`/`CONSECUTIVE_DAYS`/`RESOLUTION_SUCCESS`/`RESOLUTION_STREAK`)으로 재정의. 성장은 코인·미션 해금으로만 표현한다. ⚠️ `character_events.event_type`·`character_lines.context`의 `LEVEL_UP` enum·대사 시드는 **유지**(inert — 컬럼이 아닌 CHECK enum이라 무해, Task 028에서 정리 예정). 실적립·구매 엔진(코인)은 여전히 **Task 028 미구현**.
  - **`V19__diary_manual_emotion.sql`(적용됨 — Task 024, 감정 사용자 입력 전환)** — `diaries.emotion_label VARCHAR(20)` 추가 + `chk_diaries_done_has_emotion` DROP(감정 미입력 확정 허용). LLM 감정 분석은 flag(`record.analysis.enabled`, 기본 false)로 꺼져 감정은 **사용자 직접 입력**(프리셋 `primary_emotion` 또는 자유 텍스트 `emotion_label`, 상호 배타)이 기본이며, flag를 켜면 V7의 LLM 비동기 분석 경로가 무손상 복구된다. `emotion_types` 6종 마스터는 감정 코드의 단일 진실원으로 **유지**한다.
  - 마스터 데이터 시드(`emotion_types`, `characters`)는 해당 기능 마이그레이션 안에서 `INSERT ... ON CONFLICT DO NOTHING`(멱등)으로 넣는다. 아이템·대사·미션 카탈로그처럼 **운영 중 계속 늘어나는** 데이터는 마이그레이션이 아니라 데이터 적재 경로로 관리하고, 스키마는 건드리지 않는다(아이템 추가에 앱 배포·마이그레이션 불필요 — `character_items.image_url`만 등록하면 앱이 런타임 주입).
- **로컬 개발**: 네이티브 PostgreSQL 18(`recorme` DB/롤)에 빈 DB만 준비하면 `./gradlew bootRun` 시 Flyway가 자동 적용. DBeaver는 조회용.
- **기배포 마이그레이션 수정 금지(재확인)**: 운영 환경에서는 `flyway.clean` 비활성화(`clean-disabled=true`), 모든 변경은 **신규 버전 마이그레이션으로만** 한다. 이미 적용된 `V1~V19`는 절대 수정하지 않는다(체크섬 불일치로 기동 실패). 그래서 보상 재설계(경험치/레벨 폐기)도 V15~V17을 고치는 대신 **V18에서 컬럼·시드·CHECK를 DROP/재정의**했고, 감정 모델 변경도 V7·V8을 고치는 대신 **V19에서 컬럼 추가 + 제약 DROP**으로 처리했다(V6가 V4의 nullable을 사후에 강화한 것과 같은 패턴).
