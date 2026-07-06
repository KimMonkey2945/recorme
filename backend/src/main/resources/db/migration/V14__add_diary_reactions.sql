-- =====================================================================
-- V14__add_diary_reactions.sql — 소셜 ④ 공감(리액션)
-- 원본: docs/database.md(diary_reactions) + 승인 계획.
-- 범위: diary_reactions(1인 1회 공감) + diaries.reaction_count(비정규화 캐시).
--   댓글 없음(공감만). 향후 이모지 다종 확장 시 chk_reaction_type 집합만 넓히면 됨.
-- 공감 수는 읽기(피드) 편향이라 매 조회 COUNT 를 피하려 diaries.reaction_count 로 캐시하고,
--   리액션 INSERT/DELETE 와 같은 트랜잭션에서 서비스가 원자 증감(±1)한다(DB 트리거 미사용 방침).
-- reacted_by_me(뷰어별)는 캐시 불가 → 피드 쿼리에서 EXISTS 로 산출.
-- =====================================================================

CREATE TABLE diary_reactions (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    diary_id   BIGINT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    type       VARCHAR(20) NOT NULL DEFAULT 'EMPATHY',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_reaction_type CHECK (type IN ('EMPATHY')),
    -- 1인 1회 공감(중복·경합 방지). type 포함이라 향후 이모지 다종 확장 여지.
    CONSTRAINT uq_reaction_once  UNIQUE (diary_id, user_id, type)
);

-- 특정 일기의 공감자/카운트 조회용.
CREATE INDEX idx_diary_reactions_diary ON diary_reactions (diary_id);

-- 공감 수 캐시(비정규화). 리액션이 아직 없으므로 기존 행 백필 불필요(기본 0).
ALTER TABLE diaries
    ADD COLUMN reaction_count INT NOT NULL DEFAULT 0;
ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_reaction_count CHECK (reaction_count >= 0);
