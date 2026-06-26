package com.recordapp.domain.diary.dto;

import java.util.List;

/**
 * 월 단위 일기 작성일 요약(캘린더 표시용).
 * yearMonth 는 "yyyy-MM", dates 는 해당 월에 활성 일기가 존재하는 날짜("yyyy-MM-dd") 목록(오름차순).
 */
public record DiarySummaryResponse(
		String yearMonth,
		List<String> dates) {
}
