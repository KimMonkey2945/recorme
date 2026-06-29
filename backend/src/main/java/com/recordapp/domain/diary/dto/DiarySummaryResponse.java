package com.recordapp.domain.diary.dto;

import java.util.List;

/**
 * 월 단위 일기 요약(캘린더 표시용).
 * yearMonth 는 "yyyy-MM", days 는 해당 월에 활성 일기가 존재하는 날짜별 요약 목록(written_date 오름차순).
 * 각 항목은 날짜·분석상태와 함께 감정색·무드 이모지용 필드(primaryEmotion·moodEmoji)를 담는다.
 */
public record DiarySummaryResponse(
		String yearMonth,
		List<DiarySummaryDay> days) {
}
