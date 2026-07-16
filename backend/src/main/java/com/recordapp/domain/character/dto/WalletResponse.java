package com.recordapp.domain.character.dto;

/**
 * GET /characters/me/wallet 응답 — 코인 잔액 + 미확인 보상 수(홈 상단 배지).
 *
 * @param balance            현재 코인 잔액
 * @param unackedRewardCount 아직 확인하지 않은 보상 수(0이면 배지 숨김)
 */
public record WalletResponse(int balance, int unackedRewardCount) {
}
