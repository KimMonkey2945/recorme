package com.recordapp.domain.character.dto;

/**
 * 캐릭터 목록 항목(온보딩 좌우 비교 캐러셀 + 캐릭터 교체 화면 공용).
 *
 * <p>{@code owned} 는 MVP 에서 항상 true 다 — 캐릭터 2종은 전원 무료 개방이고, 유료·한정 캐릭터가
 * 생기면 이 필드만 실제 소유 판정으로 바꾸면 된다(앱 계약은 그대로).
 * {@code selected} 는 현재 선택 여부(온보딩 완료 전에는 전부 false).
 */
public record CharacterResponse(
		String code,
		String nameKo,
		String tagline,
		String thumbnailUrl,
		boolean owned,
		boolean selected) {
}
