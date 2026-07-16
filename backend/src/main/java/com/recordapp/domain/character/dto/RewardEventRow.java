package com.recordapp.domain.character.dto;

import java.time.OffsetDateTime;

/**
 * character_events 1행(코인 원장 = 리액션 페이로드 = 보상함 항목).
 * 보상함 목록·확정 리액션 조회가 공유하는 읽기 모델이며, payload 는 JSONB 원문(::text)으로
 * 서비스가 {@code JsonNode} 로 파싱해 응답에 싣는다.
 *
 * <p>⚠️ constructor 기반 매핑 — XML {@code <arg>} 순서가 이 record 표준 생성자와 정확히 일치해야 한다
 * (map-underscore-to-camel-case 는 constructor arg 엔 auto-apply 되지 않는다 — 도메인 공통 관례).
 *
 * @param id           이벤트 PK(커서 페이징 키)
 * @param eventType    적립 종류(DIARY_CONFIRM/RESOLUTION_SUCCESS/RESOLUTION_DAY/STREAK/ATTENDANCE …)
 * @param coinDelta    이 이벤트의 코인 변동(적립 +)
 * @param balanceAfter 적립 후 잔액 스냅샷(코인 변동 없으면 null)
 * @param payload      리액션 페이로드 JSONB 원문(대사·맥락·잔액 등)
 * @param createdAt    발생 시각
 */
public record RewardEventRow(
		long id,
		String eventType,
		int coinDelta,
		Integer balanceAfter,
		String payload,
		OffsetDateTime createdAt) {
}
