-- =====================================================================
-- V11__add_friendships.sql — 소셜 ① 친구 관계
-- 원본: docs/database.md(friendships) + 승인 계획(task-015-lively-acorn.md).
-- 범위: users.friend_code(친구코드) 컬럼 추가 + 백필 + UNIQUE,
--       friendships(친구 관계) 테이블 생성.
-- 친구 추가 경로: 친구코드 정확검색 / 닉네임 부분검색 → 요청(PENDING) → 수락(ACCEPTED).
-- 운영 안전성: friend_code 는 NOT NULL 이라 기존 행 백필이 필요하다(소규모 즉시 완료).
--   대용량이면 (nullable ADD) → (백필 배치) → (VALIDATE 후 NOT NULL) 로 분리할 것.
-- 상태 전이는 서비스가 수행(DB 트리거 미사용). gen_random_uuid()는 PG13+ 내장.
-- =====================================================================

-- ========== 친구코드(users 확장) ==========
-- 1) 우선 nullable 로 추가(즉시·무락).
ALTER TABLE users ADD COLUMN friend_code VARCHAR(8);

-- 2) 기존 행 백필: 혼동문자(I,L,O,U) 제외 32진 8자리 대문자, 충돌 시 재추첨.
--    앱/백엔드도 동일 알파벳으로 생성(FriendCodeGenerator)하며 최종 방어는 아래 UNIQUE.
DO $$
DECLARE
    r    RECORD;
    code TEXT;
    ok   BOOLEAN;
BEGIN
    FOR r IN SELECT id FROM users WHERE friend_code IS NULL LOOP
        ok := false;
        WHILE NOT ok LOOP
            SELECT string_agg(
                     substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ',
                            (floor(random() * 32)::int) + 1, 1), '')
              INTO code
              FROM generate_series(1, 8);
            BEGIN
                UPDATE users SET friend_code = code WHERE id = r.id;
                ok := true;
            EXCEPTION WHEN unique_violation THEN
                ok := false;   -- 재추첨
            END;
        END LOOP;
    END LOOP;
END $$;

-- 3) 유일성 + NOT NULL 확정(대문자 캐노니컬 저장 → 검색은 upper() 정규화, 함수 인덱스 불필요).
CREATE UNIQUE INDEX uq_users_friend_code ON users (friend_code);
ALTER TABLE users ALTER COLUMN friend_code SET NOT NULL;

-- ========== 친구 관계 ==========
-- 방향(requester/addressee)은 "누가 먼저 신청했나" 의미로 보존하고,
-- 중복 방지는 무방향 정렬쌍 유니크(uq_friendship_pair)가 담당한다
-- (컬럼쌍 UNIQUE 만으로는 A→B / B→A 역방향 중복을 못 막으므로 LEAST/GREATEST 사용).
CREATE TABLE friendships (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requester_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- 요청 보낸 쪽
    addressee_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- 요청 받은 쪽
    status       VARCHAR(20) NOT NULL DEFAULT 'PENDING',   -- PENDING/ACCEPTED/BLOCKED
    blocker_id   BIGINT REFERENCES users(id) ON DELETE CASCADE,           -- BLOCKED 시 차단 주체(방향 보존)
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,                              -- 수락/차단 전이 시각
    CONSTRAINT chk_no_self_friend    CHECK (requester_id <> addressee_id),
    CONSTRAINT chk_friendship_status CHECK (status IN ('PENDING','ACCEPTED','BLOCKED')),
    -- 상태-데이터 정합: BLOCKED 이면 차단 주체 필수.
    CONSTRAINT chk_friendship_blocker
        CHECK (status <> 'BLOCKED' OR blocker_id IS NOT NULL)
);

-- 무방향 쌍 유일성: {A,B} 조합당 1행 강제(A→B, B→A 중복 차단).
CREATE UNIQUE INDEX uq_friendship_pair
    ON friendships (LEAST(requester_id, addressee_id),
                    GREATEST(requester_id, addressee_id));

-- 받은 요청함(addressee, status='PENDING') + 친구 조회. viewer 가 addressee 인 경로.
CREATE INDEX idx_friendships_addressee ON friendships (addressee_id, status);
-- 보낸 요청 + 친구 조회. viewer 가 requester 인 경로.
CREATE INDEX idx_friendships_requester ON friendships (requester_id, status);
