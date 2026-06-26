-- =====================================================================
-- V4__diary_rich_content.sql — 일기 본문 리치 텍스트(Quill Delta JSON)화 + 순수 텍스트 분리
-- 범위: diaries 테이블만 변경한다(기능별 분할: V1=users, V2=diaries, V3=diary_images, V4=리치 본문).
--   content      : (기존 plain) → 이제 Quill Delta JSON 문자열(인라인 이미지 포함)을 저장한다. TEXT 유지.
--   content_text : 신규. 서식/이미지 마크업을 제거한 순수 텍스트(글자수 제한·목록 미리보기·향후 LLM 입력용).
--   인라인 이미지는 별도 diary_images 행으로 정합되며(서비스 reconcile), 디스크엔 상대경로만 저장한다.
-- =====================================================================

-- 1) 순수 텍스트 컬럼 추가(신규 행은 항상 채우지만, 백필 전까지 NULL 허용).
ALTER TABLE diaries ADD COLUMN content_text TEXT;

-- 2) 기존 행 백필: 순수 텍스트를 먼저 보존한다(이 시점 content 는 아직 plain).
UPDATE diaries
   SET content_text = content
 WHERE content_text IS NULL;

-- 3) 기존 plain content 를 Quill Delta JSON 으로 래핑한다.
--    기존 첨부 이미지(diary_images)가 있으면 본문 뒤에 인라인 이미지 임베드로 이어붙여
--    보존한다(인라인 통합 모델로 이전). 이미지가 없으면 텍스트 한 줄짜리 Delta가 된다.
--    결과 예: {"ops":[{"insert":"본문\n"},{"insert":{"image":"/files/..."}},{"insert":"\n"}]}
UPDATE diaries d
   SET content = (
         jsonb_build_object(
           'ops',
           jsonb_build_array(jsonb_build_object('insert', d.content_text || E'\n'))
           || COALESCE((
                SELECT jsonb_agg(op ORDER BY ord)
                FROM (
                  -- 각 이미지를 image 임베드 op + 개행 op 두 개로 펼친다(sort_order 순서 보존).
                  SELECT di.sort_order * 2 AS ord,
                         jsonb_build_object(
                           'insert',
                           jsonb_build_object('image', di.image_url)
                         ) AS op
                  FROM diary_images di WHERE di.diary_id = d.id
                  UNION ALL
                  SELECT di.sort_order * 2 + 1 AS ord,
                         jsonb_build_object('insert', E'\n') AS op
                  FROM diary_images di WHERE di.diary_id = d.id
                ) ops
              ), '[]'::jsonb)
         )
       )::text;

-- 4) 길이 제약을 content(이제 JSON, 길이 무의미)에서 content_text(순수 텍스트)로 이전한다.
ALTER TABLE diaries DROP CONSTRAINT chk_diaries_content_len;
ALTER TABLE diaries ADD CONSTRAINT chk_diaries_content_text_len
    CHECK (content_text IS NULL OR char_length(content_text) BETWEEN 1 AND 500);
