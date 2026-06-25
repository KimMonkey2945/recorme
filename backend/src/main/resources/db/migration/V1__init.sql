-- =====================================================================
-- V1__init.sql — record 초기 스키마 (회원만)
-- 원본: docs/database.md (단일 진실 공급원)
-- 범위: users 테이블만 생성한다(기능별 분할 방침).
--   diaries 는 Task 008에서 V2__add_diaries.sql 로,
--   emotion_types / themes / tracks / emotion_track_map /
--   friendships / diary_reactions 는 Phase 4 이후 Vn 마이그레이션으로 추가한다.
--   (소셜 계정·리프레시 토큰 테이블 없음 — 소셜 검증·세션은 Supabase Auth 전담,
--    백엔드는 users.supabase_uid 로 매핑 + 최초 요청 시 JIT 프로비저닝)
-- gen_random_uuid() 는 PostgreSQL 13+ 내장(별도 확장 불필요, 운영 PG18).
-- =====================================================================

-- ========== 회원 ==========
-- 이메일·소셜(카카오/구글) 가입자 모두 동일 테이블에 JIT 저장.
CREATE TABLE users (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid              UUID NOT NULL DEFAULT gen_random_uuid(),   -- 외부 노출용 식별자(공유 등)
    supabase_uid      UUID NOT NULL,                             -- Supabase auth.users.id 매핑(JWT sub)
    nickname          VARCHAR(50) NOT NULL,
    email             VARCHAR(255),                              -- 소셜 미제공 가능 → nullable
    profile_image_url TEXT,
    bio               VARCHAR(300),                              -- 자기소개(프로필 수정 대상, nullable)
    status            VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',     -- ACTIVE/DORMANT/WITHDRAWN
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    CONSTRAINT uq_users_uuid UNIQUE (uuid),
    CONSTRAINT uq_users_supabase_uid UNIQUE (supabase_uid)
);

-- 이메일 중복 방지(활성 행 한정, 대소문자 무시). 소셜 미제공(NULL)·탈퇴(soft delete)분은 제외.
CREATE UNIQUE INDEX uq_users_email_active
    ON users (lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL;
