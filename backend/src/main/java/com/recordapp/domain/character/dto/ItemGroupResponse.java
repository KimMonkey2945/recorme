package com.recordapp.domain.character.dto;

import com.fasterxml.jackson.databind.JsonNode;
import com.recordapp.domain.character.vo.AcquireType;
import com.recordapp.domain.character.vo.ItemSlot;

/**
 * 아이템 그룹 항목(옷장·상점이 공유하는 단일 목록). {@code owned} 로 옷장/상점 탭을 가른다.
 *
 * <p>{@code imageUrl}·{@code renderMeta} 는 <b>내 선택 캐릭터 기준으로 해석된 variant</b>다.
 * 해석되지 않는(해당 캐릭터용 이미지가 아직 없는) 그룹은 목록에서 <b>제외</b>된다 — 목록은 조회 경로이므로
 * 409 를 내는 대신 조용히 감추고, 착용 시도 시에만 409 ITEM_VARIANT_MISSING 으로 알린다.
 */
public record ItemGroupResponse(
		String groupCode,
		ItemSlot slot,
		String nameKo,
		String thumbnailUrl,
		AcquireType acquireType,
		int coinPrice,
		boolean owned,
		boolean equipped,
		String imageUrl,
		JsonNode renderMeta,
		MissionLockResponse lockedBy) {
}
