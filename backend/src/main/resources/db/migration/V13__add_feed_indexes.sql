-- =====================================================================
-- V13__add_feed_indexes.sql — 소셜 ③ 피드 인덱스
-- 범위: 피드 조회(본인 OR PUBLIC OR (FRIENDS AND 친구)) 커서 페이징용 부분 인덱스.
-- 정렬/커서 키는 id DESC(커서 페이징 규격과 일치 — docs 의 created_at 정정).
-- 이질적 OR 는 단일 인덱스로 못 덮으므로 브랜치별 부분 인덱스로 분리한다.
--   PRIVATE(대다수) 기록은 부분 인덱스 대상에서 빠져 인덱스가 얇게 유지된다.
-- 본인 글은 기존 idx_diaries_user_date(user_id, written_date DESC) 로 커버 가능.
-- =====================================================================

-- 공개 타임라인: PUBLIC 활성 행만, id 역순 커서.
CREATE INDEX idx_diaries_public_feed
    ON diaries (id DESC)
    WHERE visibility = 'PUBLIC' AND deleted_at IS NULL;

-- 친구 글: 친구 user_id 로 좁힌 뒤 id 역순 커서.
CREATE INDEX idx_diaries_friends_feed
    ON diaries (user_id, id DESC)
    WHERE visibility = 'FRIENDS' AND deleted_at IS NULL;
