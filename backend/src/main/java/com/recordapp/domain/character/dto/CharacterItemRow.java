package com.recordapp.domain.character.dto;

/**
 * character_items 1행(캐릭터별 렌더 variant). 카탈로그 캐시 원본.
 *
 * <p>{@code characterCode == null} 이면 공용 variant(ROOM_PROP/BACKGROUND — 체형 무관).
 * {@code renderMeta} 는 JSONB 를 {@code ::text} 로 읽은 원문이며, 캐시 적재 시 1회 파싱해
 * {@link ResolvedVariant} 로 굳힌다(요청마다 재파싱하지 않는다).
 */
public record CharacterItemRow(
		String groupCode,
		String characterCode,
		String imageUrl,
		String riveSlot,
		String renderMeta) {
}
