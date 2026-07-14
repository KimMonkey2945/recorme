package com.recordapp.domain.character.dto;

import com.recordapp.domain.character.vo.AcquireType;
import com.recordapp.domain.character.vo.ItemSlot;

/**
 * item_groups 마스터 1행(카탈로그 캐시 원본). 소유·착용이 다루는 유일한 단위.
 * 캐릭터별 이미지 차이는 {@link CharacterItemRow}(variant)가 흡수하므로 여기엔 렌더 정보가 없다.
 */
public record ItemGroupRow(
		String code,
		ItemSlot slot,
		String nameKo,
		String thumbnailUrl,
		AcquireType acquireType,
		int coinPrice,
		int sortOrder) {
}
