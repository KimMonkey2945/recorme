-- =====================================================================
-- V2__add_diaries.sql — record 일기 스키마 (diaries)
-- 원본: docs/database.md (단일 진실 공급원)
-- 범위: diaries 테이블만 생성한다(MVP).
--   theme_id/track_id(themes/tracks FK)와 공개 피드 인덱스
--   (idx_diaries_visibility_created, friendships 참조)는 Phase 4에서 추가한다.
-- gen_random_uuid() 는 PostgreSQL 13+ 내장(별도 확장 불필요, 운영 PG18).
-- =====================================================================

-- ========== 일기 ==========
-- 하루 1기록 + 수정 정책: 사용자·날짜당 활성 일기 1개(uq_diary_user_day 부분 유니크).
-- 같은 날짜 재작성은 INSERT 가 아닌 UPDATE 로 처리한다.
CREATE TABLE diaries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    share_token     UUID NOT NULL DEFAULT gen_random_uuid(),       -- 외부 노출용 식별자(공유 링크)
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    written_date    DATE NOT NULL,                                 -- 일기가 속한 날짜(하루 1기록 기준)
    visibility      VARCHAR(20) NOT NULL DEFAULT 'PRIVATE',        -- PRIVATE/FRIENDS/PUBLIC (enum 검증은 앱·백엔드)
    analysis_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',        -- PENDING/DONE/FAILED (enum 검증은 앱·백엔드)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT uq_diaries_share_token UNIQUE (share_token),
    -- content 길이 1~500: 백엔드 DiaryConstraints.CONTENT_MAX · 앱 maxLength 와 동일 상수.
    CONSTRAINT chk_diaries_content_len CHECK (char_length(content) BETWEEN 1 AND 500)
);
-- visibility/analysis_status 는 값 집합 변경 유연성을 위해 DB CHECK 를 생략한다(앱·백엔드 enum 검증).

-- 하루 1기록: 활성 행(soft delete 제외) 한정으로 user_id+written_date 유니크.
-- 소프트 삭제분은 제외되어 같은 날짜 재작성/복구가 가능하다.
CREATE UNIQUE INDEX uq_diary_user_day
    ON diaries (user_id, written_date) WHERE deleted_at IS NULL;

-- 회원별 최근 일기 목록 조회용(작성일 내림차순). 활성 행 한정.
CREATE INDEX idx_diaries_user_date
    ON diaries (user_id, written_date DESC) WHERE deleted_at IS NULL;
