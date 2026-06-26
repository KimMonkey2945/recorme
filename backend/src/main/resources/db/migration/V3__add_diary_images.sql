-- =====================================================================
-- V3__add_diary_images.sql — record 일기 첨부 사진 스키마 (diary_images)
-- 원본: docs/database.md (단일 진실 공급원)
-- 범위: diary_images 테이블만 생성한다(기능별 분할: V1=users, V2=diaries, V3=diary_images).
--   바이너리는 스토리지(디스크, StorageService)에 저장하고 DB 에는
--   상대경로(/files/diaries/yyyy/MM/{uuid}.ext)만 저장한다.
--   일기당 최대 5장 장수 제한은 서비스 레이어에서 검증한다(DB 트리거 미사용).
--   소프트삭제 컬럼을 두지 않는다 — 개별/일기 삭제 시 행을 즉시 DELETE 하고
--   디스크 파일도 함께 회수한다. diary 물리 삭제 시 FK CASCADE 로 정리된다.
-- =====================================================================

-- ========== 일기 첨부 사진 ==========
CREATE TABLE diary_images (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diary_id   BIGINT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
    image_url  TEXT NOT NULL,                 -- 스토리지 상대경로(/files/diaries/yyyy/MM/{uuid}.ext)만 저장
    sort_order INT NOT NULL DEFAULT 0,        -- 표시 순서(0부터)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 일기별 사진을 표시 순서대로 조회하기 위한 인덱스.
CREATE INDEX idx_diary_images_diary ON diary_images (diary_id, sort_order);
