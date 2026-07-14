-- =====================================================================
-- V17__add_user_character_state.sql — 캐릭터 도메인 ③ 사용자 상태
-- 원본: tasks/026-db-character-schema.md
-- 범위: user_character_state(선택·레벨) + user_item_groups(소유) + user_equipment(착용) +
--       user_progress(미션 판정 O(1) 캐시) + user_wallets(코인 잔액) +
--       character_events(★ 단일 멱등 관문).
--
-- ★ 단일 멱등 관문 — character_events(user_id, event_key) UNIQUE 한 테이블이
--   ① 멱등 게이트 ② 코인 원장 ③ 리액션 페이로드 ④ 미확인 보상 알림함을 겸한다.
--   적립·해금·미션·구매가 전부 이 관문(INSERT … ON CONFLICT DO NOTHING)을 통과하므로
--   재전달·폴러 중복·더블탭에도 중복 적립이 물리적으로 불가능하다(Task 028).
--
-- 기본 상태 행(state/wallet/progress)은 최초 접근 시 서비스가 JIT 생성한다
--   (ON CONFLICT DO NOTHING → 멱등). DB 트리거 미사용 방침 유지.
-- =====================================================================

-- ========== 캐릭터 선택·성장 ==========
CREATE TABLE user_character_state (
    user_id            BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    selected_character VARCHAR(30) REFERENCES characters(code),  -- NULL=온보딩 미완료(미선택)
    level              INT NOT NULL DEFAULT 1,
    exp                INT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_user_character_level CHECK (level >= 1),
    CONSTRAINT chk_user_character_exp   CHECK (exp >= 0)
);

-- ========== 소유(group 단위) ==========
-- ★ 소유는 캐릭터가 아니라 group 에 붙는다 → 캐릭터를 바꿔도 옷장이 그대로 따라온다.
CREATE TABLE user_item_groups (
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_code  VARCHAR(40) NOT NULL REFERENCES item_groups(code) ON DELETE CASCADE,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, group_code)
);

-- ========== 착용/진열 ==========
-- 단일 슬롯(HAT/OUTFIT/GLASSES/PROP/BACKGROUND)은 slot_index=0 한 칸뿐이므로 PK 가 "1개만" 을 강제한다.
-- ROOM_PROP 만 0~5 여섯 칸 다중 진열(Rive roomProp0..5 와 1:1 대응).
-- 소유 없는 착용은 복합 FK 로 차단한다(user_item_groups PK 참조).
-- slot 과 item_groups.slot 의 일치(HAT 칸에 OUTFIT group)는 DB 로 못 막으므로
--   서비스가 검증한다(Task 027: 400 ITEM_SLOT_MISMATCH).
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
    -- 같은 아이템을 두 칸에 겹쳐 진열하지 못하게(예: 화분 하나를 roomProp0·1 동시 배치).
    CONSTRAINT uq_user_equipment_group UNIQUE (user_id, group_code),
    -- 소유하지 않은 group 착용 불가(최종 방어선. 서비스는 409 ITEM_NOT_OWNED 로 먼저 거른다).
    CONSTRAINT fk_user_equipment_owned
        FOREIGN KEY (user_id, group_code)
        REFERENCES user_item_groups (user_id, group_code) ON DELETE CASCADE
);

-- ========== 미션 판정 캐시 ==========
-- ★ 매 확정마다 diaries/resolutions 전체를 세지 않기 위한 O(1) 캐시.
--   보상 엔진(Task 028)이 확정·완주 시 UPSERT … RETURNING 으로 갱신하고 그 값으로 미션을 판정한다.
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

-- ========== 코인 지갑 ==========
-- 잔액 음수 불가가 소비 경합의 최종 방어선.
--   서비스는 UPDATE … WHERE balance >= ? (0행이면 409 COIN_INSUFFICIENT)로 먼저 막고,
--   이 CHECK 는 그 방어가 뚫렸을 때만 발동한다(Task 028).
CREATE TABLE user_wallets (
    user_id    BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    balance    INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_user_wallets_balance CHECK (balance >= 0)
);

-- ========== ★ 단일 멱등 관문 = 코인 원장 = 리액션 페이로드 = 보상 알림함 ==========
-- event_key 규약(Task 028): 'DIARY_CONFIRM:{diaryId}' / 'RESOLUTION_SUCCESS:{resolutionId}'
--                           / 'MISSION:{missionCode}' / 'PURCHASE:{groupCode}' / 'LEVEL_UP:{level}'
-- coin_delta: 적립 +, 구매 -, 아이템만 해금 0. balance_after 는 그 시점 잔액 스냅샷(원장 감사용).
-- payload: 대사·획득 아이템·미션 등 앱 리액션 화면이 그대로 쓰는 단일 소스.
-- acked_at: NULL = 미확인 보상(알림함 뱃지 카운트 대상).
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
    -- ★ 멱등 관문의 물리적 근거. INSERT … ON CONFLICT DO NOTHING 이 0행이면 이미 처리된 이벤트.
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
