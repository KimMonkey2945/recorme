package com.recordapp.domain.diary.dto;

import java.time.LocalDate;

/**
 * 일기 목록 항목(커서 페이징용 경량 DTO).
 * <p>목록은 N+1 을 피하기 위해 첨부 사진 전체 컬렉션을 싣지 않는다 —
 * 대표 1장({@code thumbnailUrl}, sort_order 최소)과 총 장수({@code imageCount})만 제공한다.
 * 단건 화면 진입 시 {@link DiaryResponse} 로 전체 이미지를 조회한다.
 */
public record DiaryListItem(
		Long id,
		String content,
		LocalDate writtenDate,
		String analysisStatus,
		String thumbnailUrl,
		int imageCount) {
}
