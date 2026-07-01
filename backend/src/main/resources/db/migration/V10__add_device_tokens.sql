-- =====================================================================
-- V10__add_device_tokens.sql — FCM 디바이스 토큰 저장(서버 푸시)
-- 범위: 알림 인프라. 작심삼일 리마인더 외 알림에도 재사용될 범용 테이블.
--   token 은 기기당 1개(전역 유일). 재로그인/재설치 시 upsert 로 소유 재귀속.
--   무효 토큰(FCM UNREGISTERED/INVALID_ARGUMENT)은 물리 DELETE(회수형, soft delete 없음).
-- 내부 전용 테이블이라 외부 노출 uuid 는 생략(diary_images 관례).
-- =====================================================================

CREATE TABLE device_tokens (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token         TEXT NOT NULL,                             -- FCM registration token
    platform      VARCHAR(20) NOT NULL,                      -- ANDROID/IOS/WEB
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),         -- 최근 등록/갱신(스테일 토큰 정리 기준)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_device_tokens_token     UNIQUE (token),
    CONSTRAINT chk_device_tokens_platform CHECK (platform IN ('ANDROID','IOS','WEB'))
);

-- 유저 팬아웃(리마인더 발송 시 user_id → 토큰들) 조회용.
CREATE INDEX idx_device_tokens_user ON device_tokens (user_id);
