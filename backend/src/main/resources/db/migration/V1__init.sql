-- =====================================================================
-- V1__init.sql — record 초기 스키마 (MVP 범위)
-- 원본: docs/database.md (단일 진실 공급원)
-- 범위: 회원/인증/일기 4테이블만 생성.
--   emotion_types / emotion_analyses / themes / tracks / emotion_track_map /
--   friendships / diary_reactions 및 diaries.theme_id·track_id FK는
--   Phase 4(감정분석·테마·음악·공유)에서 V2+ 마이그레이션으로 추가한다.
-- =====================================================================

-- gen_random_uuid() 사용 보장(PostgreSQL 13+는 내장이나, 안전하게 확장 확보)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ========== 회원 ==========
CREATE TABLE users (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid              UUID NOT NULL DEFAULT gen_random_uuid(),   -- 외부 노출용 식별자
    nickname          VARCHAR(50) NOT NULL,
    email             VARCHAR(255),                              -- 소셜 미제공 가능 → nullable
    profile_image_url TEXT,
    status            VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',     -- ACTIVE/DORMANT/WITHDRAWN
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    CONSTRAINT uq_users_uuid UNIQUE (uuid)
);

-- ========== 소셜 계정 ==========
CREATE TABLE social_accounts (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider         VARCHAR(20) NOT NULL,                      -- KAKAO/GOOGLE/APPLE
    provider_user_id VARCHAR(191) NOT NULL,                     -- 제공자 고유 sub
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_social_provider_uid UNIQUE (provider, provider_user_id)
);
CREATE INDEX idx_social_accounts_user ON social_accounts(user_id);

-- ========== 리프레시 토큰 (회전/폐기) ==========
CREATE TABLE refresh_tokens (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(64) NOT NULL,                           -- SHA-256 해시 저장(평문 X)
    device_info VARCHAR(255),
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash)
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);

-- ========== 일기 기록 ==========
-- theme_id / track_id (적용 테마·음악 스냅샷 FK)는 Phase 4에서 추가한다.
CREATE TABLE diaries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    share_token     UUID NOT NULL DEFAULT gen_random_uuid(),    -- 공유 링크용
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    written_date    DATE NOT NULL,                              -- 기록 대상 날짜
    visibility      VARCHAR(20) NOT NULL DEFAULT 'PRIVATE',     -- PRIVATE/FRIENDS/PUBLIC
    analysis_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',     -- PENDING/DONE/FAILED
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT uq_diaries_share_token UNIQUE (share_token)
);

-- 하루 1기록 제한(수정은 동일 행 UPDATE) — 소프트 삭제분 제외(부분 유니크)
CREATE UNIQUE INDEX uq_diary_user_day ON diaries(user_id, written_date) WHERE deleted_at IS NULL;
-- 내 일기 목록(최신순) — 커서 페이징 지원
CREATE INDEX idx_diaries_user_date ON diaries(user_id, written_date DESC) WHERE deleted_at IS NULL;
