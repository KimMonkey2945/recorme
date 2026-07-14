package com.recordapp.domain.character.dto;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * 착용 항목(해석 완료). {@code imageUrl}·{@code riveSlot}·{@code renderMeta} 는
 * (groupCode + 선택 캐릭터)로 해석된 variant 값이다 — 캐릭터를 바꾸면 groupCode 는 그대로고 이 셋만 바뀐다.
 * {@code renderMeta} 는 Rive 미사용 시 플레이스홀더 렌더러(Task 029)가 쓰는 좌표/스케일(JSON 객체).
 */
public record EquippedItemResponse(
		String slot,
		short slotIndex,
		String groupCode,
		String nameKo,
		String imageUrl,
		String riveSlot,
		JsonNode renderMeta) {
}
