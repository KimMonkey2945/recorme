-- V18: 경험치/레벨 완전 제거 (보상 재설계 1단계)
--
-- 사용자 결정으로 성장(레벨·경험치) 개념을 폐기한다. 코인은 유지(기록 확정·작심삼일 완주·미션으로 적립,
-- 실적립 엔진은 Task 028). user_character_state의 level/exp 컬럼과 LEVEL 미션 규칙을 제거한다.
--
-- ⚠️ character_events.event_type·character_lines.context의 LEVEL_UP enum과 대사 시드는 이번엔 남긴다:
--    컬럼이 아닌 CHECK enum이라 level 제거만으로 앞으로 생성되지 않아(inert) 무해하고,
--    CHECK 재정의·시드 삭제 리스크만 늘어 실익이 없다. 이벤트 분류를 확정하는 Task 028에서 함께 정리한다.

-- 1) user_character_state: CHECK를 먼저 떼고 컬럼을 드롭한다.
ALTER TABLE user_character_state DROP CONSTRAINT IF EXISTS chk_user_character_level;
ALTER TABLE user_character_state DROP CONSTRAINT IF EXISTS chk_user_character_exp;
ALTER TABLE user_character_state DROP COLUMN IF EXISTS level;
ALTER TABLE user_character_state DROP COLUMN IF EXISTS exp;

-- 2) missions: LEVEL 규칙 시드를 먼저 지운 뒤 rule_type CHECK를 LEVEL 없이 재정의한다.
--    (LEVEL_5 행이 남아 있으면 새 CHECK ADD가 실패하므로 순서가 중요하다. user_missions는
--     ON DELETE CASCADE지만 순서 안전을 위해 명시적으로 먼저 지운다.)
DELETE FROM user_missions WHERE mission_code = 'LEVEL_5';
DELETE FROM missions      WHERE code = 'LEVEL_5';

ALTER TABLE missions DROP CONSTRAINT IF EXISTS chk_missions_rule_type;
ALTER TABLE missions ADD  CONSTRAINT chk_missions_rule_type
    CHECK (rule ->> 'type' IN
           ('DIARY_COUNT', 'CONSECUTIVE_DAYS', 'RESOLUTION_SUCCESS', 'RESOLUTION_STREAK'));
