package com.recordapp.domain.resolution.dto;

import com.recordapp.domain.resolution.ResolutionConstraints;
import jakarta.validation.constraints.FutureOrPresent;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 작심삼일 생성 요청. 종료일은 서버가 {@code startDate + 2} 로 파생하므로 요청에 두지 않는다.
 * 소유권은 SecurityContext 의 userId 로만 식별하므로 바디에 사용자 식별자를 두지 않는다(IDOR 차단).
 *
 * <p>{@code startDate} 는 오늘/미래만 허용한다 — {@link FutureOrPresent} 가 1차 방어이고,
 * 서비스가 KST(Asia/Seoul) 기준으로 재검증한다(서버 기본 타임존과 무관하게 판정).
 * {@code reminderTime} 은 nullable(매일 알림 벽시계 시각, NULL=알림 없음).
 */
public record CreateResolutionRequest(
		@NotBlank @Size(max = ResolutionConstraints.TITLE_MAX) String title,
		@NotNull @FutureOrPresent LocalDate startDate,
		LocalTime reminderTime) {
}
