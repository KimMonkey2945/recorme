-- =====================================================================
-- V7__add_emotion_analysis.sql — 일기별 감정·테마 분석 결과 저장
-- 범위: emotion_types 마스터 신설 + diaries 에 AI 분석 산출 컬럼 추가(기능별 분할).
--   멀티모달 LLM(Claude)이 일기 1건마다 자유 생성하는 감정/색/코멘트를 저장한다.
--   docs 의 themes 프리셋·diaries.theme_id 스냅샷 모델은 도입하지 않는다
--   (고정 테마 매핑 대신 일기별 AI 자유 생성으로 대체). 폰트(font_key)는 후속 V8.
-- 운영 안전성: 신규 컬럼은 모두 nullable·DEFAULT 없음 → 메타데이터 변경만(즉시·무백필).
--   ADD CONSTRAINT(FK/CHECK)는 기존 행 1회 검증 스캔이 있으나 현재 분석 컬럼이 전부 NULL이라
--   검증이 가볍다(대용량 운영 시엔 NOT VALID 후 VALIDATE 분리 고려).
-- =====================================================================

-- ========== 감정 마스터 ==========
-- 주감정 코드의 단일 진실원. 라벨/정렬은 여기서만 관리하고 diaries 는 code 만 참조한다.
CREATE TABLE emotion_types (
    code        VARCHAR(20) PRIMARY KEY,                 -- JOY/SADNESS/... (FK 대상)
    label_ko    VARCHAR(30) NOT NULL,                    -- 한국어 표시 라벨
    sort_order  INT NOT NULL DEFAULT 0                   -- UI 정렬 순서(작을수록 먼저)
);

-- 시드 6종(멱등: 재적용·중복 시 무시).
INSERT INTO emotion_types (code, label_ko, sort_order) VALUES
    ('JOY',     '기쁨', 10),
    ('SADNESS', '슬픔', 20),
    ('ANGER',   '분노', 30),
    ('CALM',    '평온', 40),
    ('ANXIETY', '불안', 50),
    ('NEUTRAL', '중립', 60)
ON CONFLICT (code) DO NOTHING;

-- ========== diaries 분석 컬럼 ==========
-- 전부 nullable: PENDING(분석 전) 상태에서는 비어 있고, DONE 시점에 채워진다.
ALTER TABLE diaries
    ADD COLUMN primary_emotion   VARCHAR(20),   -- 대표 감정 코드(emotion_types FK)
    ADD COLUMN background_color   VARCHAR(9),    -- 배경색 #RRGGBB 또는 #RRGGBBAA
    ADD COLUMN text_color         VARCHAR(9),    -- 본문 글자색
    ADD COLUMN accent_color       VARCHAR(9),    -- 강조색
    ADD COLUMN ai_comment         VARCHAR(200),  -- AI 한 줄 코멘트
    ADD COLUMN ai_title           VARCHAR(60),   -- AI 생성 제목
    ADD COLUMN mood_emoji         VARCHAR(8),    -- 분위기 이모지(멀티바이트 대응 여유)
    ADD COLUMN emotion_scores     JSONB,         -- 감정별 점수 분포(자유 키/값)
    ADD COLUMN analyzed_at        TIMESTAMPTZ;   -- 분석 완료 시각(사용자 편집 updated_at 과 구분)

-- 주감정 → 마스터 참조. 기존 행은 모두 NULL 이라 검증 스캔이 가볍다.
ALTER TABLE diaries
    ADD CONSTRAINT fk_diaries_emotion
    FOREIGN KEY (primary_emotion) REFERENCES emotion_types(code);

-- 색 형식 검증(NULL 허용). #RRGGBB 또는 #RRGGBBAA(8자리 알파) 만 허용.
ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_bg_color
    CHECK (background_color IS NULL OR background_color ~ '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$');
ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_text_color
    CHECK (text_color IS NULL OR text_color ~ '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$');
ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_accent_color
    CHECK (accent_color IS NULL OR accent_color ~ '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$');

-- 상태-데이터 정합: 분석 완료(DONE)면 주감정은 반드시 존재해야 한다.
-- PENDING/FAILED 상태에서는 primary_emotion NULL 을 허용한다.
ALTER TABLE diaries
    ADD CONSTRAINT chk_diaries_done_has_emotion
    CHECK (analysis_status <> 'DONE' OR primary_emotion IS NOT NULL);
