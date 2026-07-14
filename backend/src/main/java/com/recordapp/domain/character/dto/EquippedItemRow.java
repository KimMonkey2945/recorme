package com.recordapp.domain.character.dto;

/**
 * 착용 1행 + 선택 캐릭터 기준으로 <b>해석된</b> variant(매퍼의 variant 해석 조인 결과).
 * {@code renderMeta} 는 JSONB 원문(::text)이며 서비스가 응답 직전에 JsonNode 로 파싱한다.
 */
public record EquippedItemRow(
		String slot,
		short slotIndex,
		String groupCode,
		String nameKo,
		String imageUrl,
		String riveSlot,
		String renderMeta) {
}
