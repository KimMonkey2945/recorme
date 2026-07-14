package com.recordapp.domain.character.dto;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * (group_code + 선택 캐릭터)로 해석된 렌더 정보. 캐시가 파싱까지 끝낸 형태다.
 *
 * <p>API 는 group↔variant 2단 구조를 노출하지 않는다 — 응답의 {@code imageUrl} 은 언제나
 * "내 캐릭터 기준으로 해석된" 이미지다. 캐릭터를 바꾸면 같은 group 이 다른 variant 로 재해석된다.
 */
public record ResolvedVariant(
		String imageUrl,
		String riveSlot,
		JsonNode renderMeta) {
}
