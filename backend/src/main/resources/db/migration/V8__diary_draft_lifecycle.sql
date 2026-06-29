-- =====================================================================
-- V8__diary_draft_lifecycle.sql — 일기 등록/확정 라이프사이클
-- 일기는 등록 시 미확정(DRAFT)으로 출발해 수정 가능·미분석 상태이며,
-- '오늘을 기억하기'로 확정하면 PENDING 으로 전이되어 1회 감정 분석된다.
-- 운영 안전성: DEFAULT 변경·CHECK 추가만(메타데이터 변경, 백필 없음).
--   기존 행의 PENDING/DONE/FAILED 는 CHECK 집합에 모두 포함되어 통과한다.
-- =====================================================================

-- 등록 기본값을 DRAFT 로 전환(이전 기본값 'PENDING' 대체).
ALTER TABLE diaries ALTER COLUMN analysis_status SET DEFAULT 'DRAFT';

-- 허용 상태값 집합 명시(기존 데이터 PENDING/DONE/FAILED 모두 통과, 백필 없음).
-- V7 의 chk_diaries_done_has_emotion 과 충돌 없음: DRAFT 는 primary_emotion NULL 허용.
ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_analysis_status
    CHECK (analysis_status IN ('DRAFT','PENDING','DONE','FAILED'));
