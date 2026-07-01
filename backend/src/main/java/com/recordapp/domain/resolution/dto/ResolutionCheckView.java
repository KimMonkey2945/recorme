package com.recordapp.domain.resolution.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 결심 상세에 포함되는 일별 체크 1행 뷰(1·2·3일차).
 * <p>{@code completedAt} 은 nullable — DONE 전이 시각이며, PENDING/MISSED 면 NULL 이다.
 */
public record ResolutionCheckView(
		LocalDate checkDate,
		Short dayIndex,
		String status,
		OffsetDateTime completedAt) {
}
