package com.recordapp.domain.character.dto;

/**
 * user_character_state 1행. {@code selectedCharacter == null} 이면 온보딩 미완료(캐릭터 미선택)다.
 * 앱은 이 null 을 보고 온보딩으로 리다이렉트하므로, 미선택 사용자에게도 404 가 아니라 200 을 준다.
 */
public record UserCharacterStateRow(
		String selectedCharacter) {
}
