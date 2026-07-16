-- =====================================================================
-- V20__reward_engine_event_types.sql — 보상 엔진(Task 028) 트리거 확장
-- 원본: tasks/028-backend-reward-engine.md, docs/coin-rewards.md
--
-- 코인 적립 트리거는 앞으로 계속 추가·수정·제거된다(출석·기록·작심삼일 1·2일차·완주·연속 마일스톤 …).
-- event_type 을 고정 CHECK 로 묶으면 트리거가 늘 때마다 마이그레이션이 필요해지므로,
-- CHECK 를 제거해 새 트리거를 코드/설정만으로 추가할 수 있게 한다.
--
-- 무결성은 그대로 유지된다:
--   ① 중복 적립 방어 = uq_character_events_key(user_id, event_key) UNIQUE (불변)
--   ② 잔액 음수 방어 = chk_character_events_balance / user_wallets.chk_user_wallets_balance (불변)
--   event_type 은 이제 자유 라벨(VARCHAR(30))이며 애플리케이션(CharacterRewardService)이 값을 관리한다.
--
-- 참고: V18 레벨 폐기로 inert 상태였던 'LEVEL_UP' 도 이 CHECK 제거로 함께 정리된다
--       (Task 028 문서가 예고한 정리 지점).
-- =====================================================================

ALTER TABLE character_events DROP CONSTRAINT IF EXISTS chk_character_events_type;
