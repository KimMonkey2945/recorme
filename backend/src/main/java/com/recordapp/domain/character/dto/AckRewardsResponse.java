package com.recordapp.domain.character.dto;

/**
 * POST /characters/me/rewards/ack 응답 — 보상함 확인 결과.
 *
 * @param acked              이번에 확인 처리된 미확인 보상 수
 * @param unackedRewardCount 확인 후 남은 미확인 수(전체 확인이므로 0)
 */
public record AckRewardsResponse(int acked, int unackedRewardCount) {
}
