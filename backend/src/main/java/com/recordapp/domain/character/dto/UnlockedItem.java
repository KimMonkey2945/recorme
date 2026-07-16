package com.recordapp.domain.character.dto;

/**
 * 월간 회고의 획득 아이템 1행. imageUrl 은 <b>내 선택 캐릭터 기준으로 해석된</b> variant 이미지다
 * (group↔variant 2단 구조는 노출하지 않는다).
 *
 * @param groupCode 아이템 group 코드
 * @param nameKo    아이템 한국어 이름
 * @param imageUrl  내 캐릭터 기준 렌더 이미지(해석 실패 시 null)
 */
public record UnlockedItem(
		String groupCode,
		String nameKo,
		String imageUrl) {
}
