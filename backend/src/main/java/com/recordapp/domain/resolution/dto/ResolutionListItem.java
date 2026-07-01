package com.recordapp.domain.resolution.dto;

import java.time.LocalDate;

/**
 * 결심 목록 항목(진행/성공/실패 탭 + 최신순 커서용 경량 DTO).
 * <p>상세({@link ResolutionDetailResponse})의 체크 컬렉션 대신, 3일 진행 도트 렌더용으로
 * {@code dayStatuses} 만 얇게 싣는다 — day_index 오름차순 체크 상태를 콤마로 결합한 문자열
 * (예: {@code "DONE,PENDING,PENDING"}). 클라이언트가 콤마로 분해해 1·2·3일차 도트로 그린다.
 * (DiaryListItem 이 thumbnailUrl·imageCount 만 스칼라로 싣는 것과 동일한 경량화 전략.)
 */
public record ResolutionListItem(
		Long id,
		String title,
		LocalDate startDate,
		LocalDate endDate,
		String status,
		Short streakSeq,
		String dayStatuses) {
}
