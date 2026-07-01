-- =====================================================================
-- V9__add_resolutions.sql — 작심삼일(3일 결심) 스키마
-- 범위: resolutions(결심) + resolution_checks(일별 체크) 한 세트 생성.
--   작심삼일 = 시작일 + 할일(title) + 3일. 매일 '완료' 체크, 3일 완료=SUCCESS,
--   하루라도 그 날(KST 자정 전) 미완료=FAILED. 동시 여러 개 진행 가능.
--   연장 = 같은 할일 '다음 3일' 새 resolution + streak_group 으로 연결.
-- 상태: ONGOING → SUCCESS | FAILED (터미널). '예정'(미래 시작)은 별도 상태를
--   두지 않고 start_date > today 로 파생, 취소는 soft delete(deleted_at)로 처리한다.
-- 상태 전이는 서비스/배치가 수행(DB 트리거 미사용). gen_random_uuid()는 PG13+ 내장.
-- =====================================================================

-- ========== 결심(작심삼일) ==========
CREATE TABLE resolutions (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title            VARCHAR(100) NOT NULL,                     -- 할일 제목
    start_date       DATE NOT NULL,                             -- 시작일(오늘/미래, 과거 금지는 서비스 검증)
    end_date         DATE NOT NULL,                             -- 종료일 = start_date + 2 (3일)
    status           VARCHAR(20) NOT NULL DEFAULT 'ONGOING',    -- ONGOING/SUCCESS/FAILED
    reminder_time    TIME,                                      -- 매일 알림 시각(KST 벽시계). NULL=알림 없음
    streak_group_id  UUID NOT NULL DEFAULT gen_random_uuid(),   -- 연장 체인 묶음(첫 도전 생성, 연장 시 복사)
    streak_seq       SMALLINT NOT NULL DEFAULT 1,               -- 체인 내 순번(1부터, 연장 시 +1) = "N연속"
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ,
    -- title 길이 1~100: 백엔드 ResolutionConstraints.TITLE_MAX 와 동일 상수.
    CONSTRAINT chk_resolutions_title_len  CHECK (char_length(title) BETWEEN 1 AND 100),
    -- 3일 span 불변식(불변 표현이라 CHECK 가능). '시작일 오늘/미래'는 비불변이라 서비스 검증.
    CONSTRAINT chk_resolutions_span       CHECK (end_date = start_date + 2),
    CONSTRAINT chk_resolutions_status     CHECK (status IN ('ONGOING','SUCCESS','FAILED')),
    CONSTRAINT chk_resolutions_streak_seq CHECK (streak_seq >= 1),
    -- 같은 체인 내 순번 중복(더블 연장 경합) 방지.
    CONSTRAINT uq_resolutions_streak_seq  UNIQUE (streak_group_id, streak_seq)
);

-- 리스트(진행/성공/실패 탭 + 최신순 커서). user_id·status 등치 후 (start_date,id) 정렬 무료.
CREATE INDEX idx_resolutions_user_status_start
    ON resolutions (user_id, status, start_date DESC, id DESC) WHERE deleted_at IS NULL;

-- ========== 일별 체크 ==========
-- resolution 생성 시 3행(day_index 1~3, check_date = start_date + 0/1/2) 프리생성.
-- user_id 는 월 캘린더를 단일 테이블 range scan 으로 끝내기 위한 비정규화.
-- deleted_at 없음: 부모 soft delete 시 캘린더 쿼리가 r.deleted_at IS NULL 로 거르고,
--   부모 물리 삭제 시 FK CASCADE 로 정리(diary_images 관례와 동일).
CREATE TABLE resolution_checks (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resolution_id  BIGINT NOT NULL REFERENCES resolutions(id) ON DELETE CASCADE,
    user_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- 캘린더 직접조회용 비정규화
    check_date     DATE NOT NULL,                             -- 이 체크가 속한 날짜
    day_index      SMALLINT NOT NULL,                         -- 1..3 (1·2·3일차)
    status         VARCHAR(20) NOT NULL DEFAULT 'PENDING',    -- PENDING/DONE/MISSED
    completed_at   TIMESTAMPTZ,                               -- DONE 전이 시각(NULL=미완료)
    reminded_on    DATE,                                      -- 리마인더 발송한 날짜(하루 1회 멱등 선점 키)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_resolution_checks_day    CHECK (day_index BETWEEN 1 AND 3),
    CONSTRAINT chk_resolution_checks_status CHECK (status IN ('PENDING','DONE','MISSED')),
    -- 상태-데이터 정합: DONE 이면 완료시각 필수(PENDING/MISSED 는 NULL 허용).
    CONSTRAINT chk_resolution_checks_done   CHECK (status <> 'DONE' OR completed_at IS NOT NULL),
    CONSTRAINT uq_resolution_checks_day     UNIQUE (resolution_id, check_date),  -- 하루 1체크(중복·경합 방지)
    CONSTRAINT uq_resolution_checks_idx     UNIQUE (resolution_id, day_index)    -- 3행 프리생성 무결성
);

-- 월별 캘린더: 특정 유저의 월 구간 체크를 단일 테이블 range scan 으로.
CREATE INDEX idx_resolution_checks_user_date
    ON resolution_checks (user_id, check_date);

-- 자정 실패배치(check_date < today) + FCM 리마인더(check_date = today) 공용.
-- PENDING 행만 얇게 인덱싱 → 남은 미완료만 스캔(부분 인덱스로 배치 비용 상수 유지).
CREATE INDEX idx_resolution_checks_pending
    ON resolution_checks (check_date) WHERE status = 'PENDING';
