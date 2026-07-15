package com.recordapp.domain.character.dto;

import java.util.List;

/**
 * GET /characters/me 응답 — 캐릭터 홈이 <b>한 번에</b> 그리는 데 필요한 전부.
 *
 * <p>★ 캐릭터 미선택(신규 가입 직후) 사용자에게도 <b>200 + {@code character: null}</b> 을 준다(404 아님).
 * 앱은 이 null 을 온보딩 미완료 신호로 읽는다. 이때 coinBalance=0 / equipment=[] 이다.
 * PUT /characters/me/selection · PUT /characters/me/equipment 응답도 같은 형태다.
 *
 * <p>레벨/경험치는 보상 재설계(1단계)에서 제거됐다 — 성장은 코인·미션 해금으로만 표현한다.
 */
public record MyCharacterResponse(
		SelectedCharacterResponse character,
		int coinBalance,
		int unackedRewardCount,
		List<EquippedItemResponse> equipment) {
}
