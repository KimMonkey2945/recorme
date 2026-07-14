package com.recordapp.domain.character.dto;

/**
 * characters 마스터 1행(카탈로그 캐시 원본). 활성 캐릭터만 적재한다.
 * riveArtboard 는 앱 렌더러가 참조하는 아트보드명이라 목록 응답에는 싣지 않고 선택 캐릭터 응답에만 싣는다.
 */
public record CharacterRow(
		String code,
		String nameKo,
		String tagline,
		String riveArtboard,
		String thumbnailUrl) {
}
