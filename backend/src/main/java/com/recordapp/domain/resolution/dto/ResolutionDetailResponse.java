package com.recordapp.domain.resolution.dto;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;

/**
 * 결심 단건 상세 응답. 헤더(제목·기간·상태·알림·연속 순번)와 3일치 체크 목록을 함께 담는다.
 *
 * <p>{@code streakSeq} 는 연장 체인 내 순번(1부터, "N연속")이다. {@code reminderTime} 은 nullable(알림 없음).
 * {@code checks} 는 day_index 오름차순의 1·2·3일차 체크(생성 시 3행 프리생성)다.
 */
public record ResolutionDetailResponse(
		Long id,
		String title,
		LocalDate startDate,
		LocalDate endDate,
		String status,
		LocalTime reminderTime,
		Short streakSeq,
		List<ResolutionCheckView> checks) {
}
