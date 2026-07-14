package com.recordapp.domain.character.dto;

import java.util.List;

/** GET /characters/items?slot= 응답(슬롯 생략 시 전체). */
public record ItemGroupListResponse(
		List<ItemGroupResponse> items) {
}
