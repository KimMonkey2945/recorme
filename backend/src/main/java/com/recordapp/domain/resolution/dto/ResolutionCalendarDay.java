package com.recordapp.domain.resolution.dto;

import java.time.LocalDate;

/**
 * 월별 캘린더의 한 칸(날짜×결심) 항목. 하루에 여러 결심이 진행될 수 있어 (날짜, 결심)당 1행이다.
 * <p>{@code resolutionStatus} 는 소속 결심의 상태(ONGOING/SUCCESS/FAILED),
 * {@code checkStatus} 는 그 날짜 체크의 상태(PENDING/DONE/MISSED)다.
 * 캘린더는 이 둘을 조합해 날짜별 진행 배지를 그린다.
 */
public record ResolutionCalendarDay(
		LocalDate date,
		Long resolutionId,
		String title,
		String resolutionStatus,
		String checkStatus) {
}
