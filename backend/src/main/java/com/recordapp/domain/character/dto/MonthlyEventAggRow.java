package com.recordapp.domain.character.dto;

/**
 * 월간 코인/완주 집계 매퍼 원행(character_events 를 created_at 월 범위로 한 번에 집계).
 *
 * @param coinEarned             이달 획득 코인 합(coin_delta &gt; 0 만 — 구매 소비 제외)
 * @param resolutionSuccessCount 이달 작심삼일 완주 이벤트 수
 */
public record MonthlyEventAggRow(
		int coinEarned,
		int resolutionSuccessCount) {
}
