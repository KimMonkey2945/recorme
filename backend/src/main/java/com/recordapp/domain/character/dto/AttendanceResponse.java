package com.recordapp.domain.character.dto;

/**
 * POST /characters/me/attendance 응답 — 출석 적립 결과.
 *
 * @param granted 이번 호출로 적립됐는지(false = 오늘 이미 출석했거나 출석 보상이 꺼짐)
 * @param coin    출석 적립액(기준값)
 * @param balance 현재 코인 잔액
 */
public record AttendanceResponse(boolean granted, int coin, int balance) {
}
