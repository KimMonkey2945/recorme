package com.recordapp.domain.resolution.dto;

import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 결심 단건의 스칼라 필드 매핑용 내부 DTO(resolutions 행).
 * <p>서비스가 상태 전이·연장 판정에 쓰고, 체크 목록과 조립해 {@link ResolutionDetailResponse} 로 매핑한다.
 * {@code streakGroupId} 는 UUID 를 ::text 로 캐스팅해 String 으로 받는다(연장 체인 식별·중복 선검사용).
 */
public record ResolutionRow(
		Long id,
		String title,
		LocalDate startDate,
		LocalDate endDate,
		String status,
		LocalTime reminderTime,
		String streakGroupId,
		Short streakSeq) {
}
