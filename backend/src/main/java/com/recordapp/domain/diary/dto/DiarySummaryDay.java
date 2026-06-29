package com.recordapp.domain.diary.dto;

/**
 * 캘린더의 하루 1칸을 그리기 위한 일자별 요약 항목.
 * <p>캘린더는 날짜마다 감정색(primaryEmotion 기반)과 무드 이모지(moodEmoji)를 표시한다.
 *
 * <p>primaryEmotion·moodEmoji 는 nullable 이다 — 감정 분석이 완료(DONE)된 기록만 값을 가지며,
 * 미확정(DRAFT)·분석중(PENDING)·실패(FAILED)면 DB 컬럼이 NULL 이라 그대로 NULL 로 내려간다.
 * 클라이언트는 analysisStatus 로 표시 상태를 분기한다(예: DONE 만 감정색·이모지 렌더).
 */
public record DiarySummaryDay(
		String date,
		String analysisStatus,
		String primaryEmotion,
		String moodEmoji) {
}
