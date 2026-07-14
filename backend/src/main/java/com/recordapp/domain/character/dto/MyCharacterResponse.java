package com.recordapp.domain.character.dto;

import java.util.List;

/**
 * GET /characters/me 응답 — 캐릭터 홈이 <b>한 번에</b> 그리는 데 필요한 전부.
 *
 * <p>★ 캐릭터 미선택(신규 가입 직후) 사용자에게도 <b>200 + {@code character: null}</b> 을 준다(404 아님).
 * 앱은 이 null 을 온보딩 미완료 신호로 읽는다. 이때 level=1 / exp=0 / coinBalance=0 / equipment=[] 이다.
 * PUT /characters/me/selection · PUT /characters/me/equipment 응답도 같은 형태다.
 */
public record MyCharacterResponse(
		SelectedCharacterResponse character,
		int level,
		int exp,
		int expToNext,
		int coinBalance,
		int unackedRewardCount,
		List<EquippedItemResponse> equipment) {
}
