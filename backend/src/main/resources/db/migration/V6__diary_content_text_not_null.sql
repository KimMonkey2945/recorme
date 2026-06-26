-- =====================================================================
-- V6__diary_content_text_not_null.sql — content_text NOT NULL 강화
-- V4에서 추가한 content_text는 백필 전까지 NULL을 허용했으나, 활성 일기에서는
-- 항상 존재해야 한다(앱이 항상 전송, 목록 미리보기·글자수 제한·향후 LLM 입력 기준).
-- V4 백필로 기존 행은 모두 채워졌으므로 안전하게 NOT NULL로 강화하고,
-- NULL 허용을 뺀 길이 제약으로 교체한다. (V4는 이미 적용되어 수정 불가 → 별도 마이그레이션)
-- =====================================================================

ALTER TABLE diaries ALTER COLUMN content_text SET NOT NULL;

ALTER TABLE diaries DROP CONSTRAINT chk_diaries_content_text_len;
ALTER TABLE diaries ADD CONSTRAINT chk_diaries_content_text_len
    CHECK (char_length(content_text) BETWEEN 1 AND 500);
