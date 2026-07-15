-- 감정 축소(Task 024): LLM 자동 분석을 flag로 끄고 감정을 사용자 직접 입력으로 전환한다.
-- 프리셋 감정은 기존 primary_emotion(FK→emotion_types)을 재사용하고, 자유 텍스트 감정만 신규 컬럼을 둔다.
-- (마이그레이션 번호: V18은 캐릭터 보상 재설계 V18__drop_level_exp.sql이 선점 → 감정은 V19.)

-- 사용자 직접 입력용 자유 텍스트 감정 라벨(≤20자). 프리셋(primary_emotion)과 상호 배타로 저장한다.
ALTER TABLE diaries ADD COLUMN emotion_label VARCHAR(20);

-- 확정(DONE) 시 대표 감정을 강제하던 정합 CHECK를 제거한다 —
-- 감정은 이제 선택 사항이므로 감정 미입력 확정(DONE)도 허용해야 한다.
ALTER TABLE diaries DROP CONSTRAINT IF EXISTS chk_diaries_done_has_emotion;
