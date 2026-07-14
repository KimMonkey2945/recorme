package com.recordapp.domain.character.dto;

/** 선택된 캐릭터 요약(캐릭터 홈 렌더용). riveArtboard 로 앱이 아트보드를 띄운다. */
public record SelectedCharacterResponse(
		String code,
		String nameKo,
		String riveArtboard,
		String thumbnailUrl) {
}
