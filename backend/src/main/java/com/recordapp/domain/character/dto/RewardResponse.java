package com.recordapp.domain.character.dto;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.OffsetDateTime;

/**
 * 보상 1건 응답 — 보상함 목록 항목이자 확정 리액션의 표현.
 * payload 는 대사·맥락·잔액을 담은 JSON 그대로이며, 앱 리액션 오버레이(Task 032)의 단일 소스다.
 *
 * @param id           이벤트 PK(커서 페이징 키)
 * @param eventType    적립 종류(DIARY_CONFIRM/RESOLUTION_SUCCESS/RESOLUTION_DAY/STREAK/ATTENDANCE …)
 * @param coinDelta    코인 변동(적립 +)
 * @param balanceAfter 적립 후 잔액(없으면 null)
 * @param payload      리액션 페이로드(context/coin/balance/line/riveTrigger). null 일 수 있다.
 * @param createdAt    발생 시각
 */
public record RewardResponse(
		long id,
		String eventType,
		int coinDelta,
		Integer balanceAfter,
		JsonNode payload,
		OffsetDateTime createdAt) {
}
