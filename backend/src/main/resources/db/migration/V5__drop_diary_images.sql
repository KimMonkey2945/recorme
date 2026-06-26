-- =====================================================================
-- V5__drop_diary_images.sql — diary_images 테이블 제거(content 단일 진실원 전환)
-- 범위: diary_images 테이블만 제거한다(기능별 분할: V1=users, V2=diaries,
--   V3=diary_images, V4=리치 본문, V5=diary_images 제거).
--   일기 본문(diaries.content)이 Quill Delta JSON 으로 인라인 이미지를 직접 임베드하므로
--   content 가 이미지 메타의 단일 진실 공급원이 된다 → 별도 diary_images 행이 불필요.
--   V4 가 기존 diary_images 행을 content Delta 의 인라인 임베드로 이미 폴드해 두었으므로
--   데이터 이전은 불필요하다. 디스크 파일은 content 가 참조하므로 보존된다
--   (회수는 서비스가 content 파싱으로 수행).
--   인덱스 idx_diary_images_diary 는 테이블과 함께 제거된다.
-- =====================================================================

DROP TABLE IF EXISTS diary_images;
