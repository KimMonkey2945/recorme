-- =====================================================================
-- V12__diary_visibility_check.sql — 소셜 ② 공개범위 무결성
-- 범위: diaries.visibility 값 집합을 CHECK 로 고정(PRIVATE/FRIENDS/PUBLIC).
--   share_token(공유 링크용 UUID)·visibility 컬럼 자체는 V2 에 이미 존재하므로 신규 컬럼 없음.
--   피드 정확성이 visibility 값에 의존하므로(오타 값이면 조용히 피드 누락) CHECK 로 침묵 버그를 차단한다.
-- 운영 안전성: 기존 행 1회 검증 스캔(짧은 락)이 있으나 소규모 즉시 완료.
--   대용량이면 ADD CONSTRAINT ... NOT VALID 후 한가할 때 VALIDATE CONSTRAINT 로 분리할 것.
-- =====================================================================

ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_visibility
    CHECK (visibility IN ('PRIVATE', 'FRIENDS', 'PUBLIC'));
