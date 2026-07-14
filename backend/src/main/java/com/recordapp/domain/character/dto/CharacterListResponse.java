package com.recordapp.domain.character.dto;

import java.util.List;

/**
 * GET /characters 응답. {@code selectedCharacter == null} 이면 온보딩 미완료(앱이 온보딩으로 리다이렉트).
 */
public record CharacterListResponse(
		String selectedCharacter,
		List<CharacterResponse> items) {
}
