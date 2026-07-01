package com.recordapp.domain.resolution.dto;

import java.time.LocalTime;

/**
 * 작심삼일 연장 요청. 성공(SUCCESS)한 결심의 '다음 3일'을 같은 streak_group 으로 이어 붙인다.
 * 제목·기간은 이전 결심에서 승계하므로 요청 바디에는 알림 시각만 둔다.
 *
 * <p>{@code reminderTime} 은 nullable — 지정하면 새 결심에 적용하고, 미지정(null)이면 이전 결심의 알림 시각을 그대로 승계한다.
 */
public record ExtendResolutionRequest(
		LocalTime reminderTime) {
}
