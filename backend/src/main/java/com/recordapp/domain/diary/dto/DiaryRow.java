package com.recordapp.domain.diary.dto;

import java.time.LocalDate;

/**
 * 일기 단건의 스칼라 필드 매핑용 내부 DTO.
 * <p>인라인 이미지는 본문(content, Quill Delta JSON)에 직접 임베드되므로 별도 컬렉션 매핑이 필요 없다 —
 * 서비스 계층이 이 스칼라 record 를 {@link DiaryResponse} 로 그대로 매핑한다.
 */
public record DiaryRow(
		Long id,
		String shareToken,
		String content,
		String contentText,
		LocalDate writtenDate,
		String visibility,
		String analysisStatus) {
}
