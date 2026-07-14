-- =====================================================================
-- V16__add_missions.sql — 캐릭터 도메인 ② 미션(유일한 해금 경로)
-- 원본: tasks/026-db-character-schema.md
-- 범위: missions(미션 마스터) + user_missions(달성 이력).
--
-- 판정은 DB 트리거가 아니라 MissionEvaluator(Task 028, 순수 함수)가 한다.
--   rule(JSONB) + user_progress(O(1) 캐시) 만 보고 판정하므로 매 확정마다 전체 기록을 세지 않는다.
-- rule 타입(★ 감정 규칙 없음):
--   {"type":"DIARY_COUNT",        "count":10}   confirmed_diary_count       >= count
--   {"type":"CONSECUTIVE_DAYS",   "days":7}     consecutive_days            >= days
--   {"type":"RESOLUTION_SUCCESS", "count":1}    resolution_success_count    >= count
--   {"type":"RESOLUTION_STREAK",  "seq":3}      max_streak_seq              >= seq   (V9 resolutions.streak_seq 재사용)
--   {"type":"LEVEL",              "level":5}    user_character_state.level  >= level
-- 보상 지급도 character_events(user_id, event_key='MISSION:{code}') 멱등 관문을 통과한다(V17).
-- =====================================================================

-- ========== 미션 마스터 ==========
CREATE TABLE missions (
    code              VARCHAR(40) PRIMARY KEY,              -- DIARY_10 등 (event_key 'MISSION:{code}' 에 사용)
    title             VARCHAR(60) NOT NULL,
    description       VARCHAR(200) NOT NULL,
    rule              JSONB NOT NULL,                       -- 판정 규칙(위 5종). MissionEvaluator 가 해석
    coin_reward       INT NOT NULL DEFAULT 0,               -- 코인 보상(0 = 없음)
    item_group_reward VARCHAR(40) REFERENCES item_groups(code),  -- 아이템 해금 보상(group 단위, NULL=없음)
    sort_order        INT NOT NULL DEFAULT 0,
    active            BOOLEAN NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_missions_coin CHECK (coin_reward >= 0),
    -- 보상 없는 미션 금지: 코인이든 아이템이든 하나는 반드시 있어야 한다.
    CONSTRAINT chk_missions_reward
        CHECK (coin_reward > 0 OR item_group_reward IS NOT NULL),
    -- rule 타입 오타 방어(감정 규칙은 의도적으로 없음). 타입 추가 시 이 집합만 넓힌다.
    CONSTRAINT chk_missions_rule_type
        CHECK (rule ->> 'type' IN
               ('DIARY_COUNT','CONSECUTIVE_DAYS','RESOLUTION_SUCCESS','RESOLUTION_STREAK','LEVEL'))
);

-- 미션 목록(활성 행 한정, 정렬 순).
CREATE INDEX idx_missions_active ON missions (sort_order) WHERE active;

-- ========== 달성 이력 ==========
-- (user_id, mission_code) PK 자체가 "미션당 1회 달성" 을 강제한다.
-- 보상 중복 지급 방지는 character_events 멱등 관문이, 이력 중복은 이 PK 가 담당한다(이중 방어).
CREATE TABLE user_missions (
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mission_code VARCHAR(40) NOT NULL REFERENCES missions(code) ON DELETE CASCADE,
    achieved_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, mission_code)
);

-- ========== 초기 미션 시드 ==========
-- 기록 습관(DIARY_COUNT/CONSECUTIVE_DAYS) + 작심삼일(RESOLUTION_*) + 성장(LEVEL) 을 고루 커버한다.
-- 아이템 보상은 V15 의 MISSION 그룹(HAT_PARTY·BG_COZY_ROOM)을 해금한다.
INSERT INTO missions (code, title, description, rule, coin_reward, item_group_reward, sort_order) VALUES
    ('DIARY_10',      '기록 10개',       '기록을 10개 확정하면 파티 모자를 드려요.',
     '{"type":"DIARY_COUNT","count":10}',        50, 'HAT_PARTY',     10),
    ('STREAK_7',      '7일 연속 기록',   '7일 연속으로 기록을 확정해 보세요.',
     '{"type":"CONSECUTIVE_DAYS","days":7}',    100, 'BG_COZY_ROOM',  20),
    ('RESOL_1',       '첫 작심삼일 완주', '작심삼일을 처음으로 완주해 보세요.',
     '{"type":"RESOLUTION_SUCCESS","count":1}',  30, NULL,            30),
    ('RESOL_STREAK_3','3연속 작심삼일',  '같은 결심을 3번 연속(9일) 이어가 보세요.',
     '{"type":"RESOLUTION_STREAK","seq":3}',    150, NULL,            40),
    ('LEVEL_5',       '레벨 5 달성',     '캐릭터를 레벨 5까지 키워 보세요.',
     '{"type":"LEVEL","level":5}',               80, NULL,            50)
ON CONFLICT (code) DO NOTHING;
