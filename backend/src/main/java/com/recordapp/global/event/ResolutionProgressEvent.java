package com.recordapp.global.event;

/**
 * 작심삼일 진척(1·2일차 달성 / 완주) 도메인 이벤트.
 *
 * <p>{@link DiaryConfirmedEvent} 와 같은 단방향 디커플링 — resolution 도메인은 character(보상)를 모른다.
 * {@code ResolutionService.completeToday} 가 이 이벤트를 발행하고, 보상 적립은 character 도메인의
 * 리스너가 AFTER_COMMIT 으로 처리한다(완주 SUCCESS 전이가 커밋된 뒤에만 코인이 나간다).
 *
 * <p>coin-rewards.md 기준: 1일차 +15, 2일차 +15, 완주 +50. day 별로 event_key 가 갈린다
 * ({@code RESOLUTION_DAY:{resolutionId}:{day}} / 완주는 {@code RESOLUTION_SUCCESS:{resolutionId}}).
 *
 * @param userId       사용자 내부 PK
 * @param resolutionId 결심 PK(멱등 키)
 * @param dayOrdinal   방금 완료한 일차(1 또는 2). 완주(day3)는 completed=true 로 표현하며 이 값은 3이다.
 * @param completed    3일 완주(ONGOING→SUCCESS)가 이 요청으로 확정됐는지
 * @param streakSeq    연장 순번(완주 시 user_progress.max_streak_seq 갱신용)
 */
public record ResolutionProgressEvent(
		long userId,
		long resolutionId,
		int dayOrdinal,
		boolean completed,
		int streakSeq) {
}
