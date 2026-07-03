package com.recordapp.domain.resolution.dto;

import com.recordapp.domain.resolution.ResolutionConstraints;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.LocalTime;

/**
 * 작심삼일 수정 요청. 진행 중(ONGOING) 결심의 제목·알림 시각만 수정한다.
 * 시작일은 수정 대상이 아니다 — 시작일을 바꾸면 종료일과 3일 체크(check_date)를 모두 재계산해야 하고
 * 이미 진행된 체크와 충돌하므로, 시작일 변경은 삭제 후 재작성으로 유도한다.
 * 소유권은 SecurityContext 의 userId 로만 식별하므로 바디에 사용자 식별자를 두지 않는다(IDOR 차단).
 *
 * <p>{@code reminderTime} 은 nullable(매일 알림 벽시계 시각, NULL=알림 없음/해제).
 */
public record UpdateResolutionRequest(
		@NotBlank @Size(max = ResolutionConstraints.TITLE_MAX) String title,
		LocalTime reminderTime) {
}
