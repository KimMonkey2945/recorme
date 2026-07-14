package com.recordapp.domain.character.dto;

/**
 * user_progress 1행 — 미션 판정 O(1) 캐시. 매 조회마다 diaries/resolutions 를 세지 않기 위한 스냅샷이다.
 * 갱신은 보상 엔진(Task 028)이 확정·완주 시 UPSERT … RETURNING 으로 수행한다.
 */
public record UserProgressRow(
		int confirmedDiaryCount,
		int consecutiveDays,
		int resolutionSuccessCount,
		int maxStreakSeq) {

	/** JIT 직후·행 부재 시의 0 스냅샷(진행률 산출을 null 분기 없이 통일). */
	public static UserProgressRow zero() {
		return new UserProgressRow(0, 0, 0, 0);
	}
}
