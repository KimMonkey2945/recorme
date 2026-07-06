package com.recordapp.domain.diary.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 공개범위 변경 요청(PATCH /diaries/{id}/visibility). 본문은 건드리지 않고 visibility 만 바꾼다
 * (확정 기록도 허용 — content 불변성과 분리). 값 집합 검증은 서비스에서 수행한다(허용 외 값 → VALIDATION_ERROR).
 */
public record UpdateVisibilityRequest(@NotBlank String visibility) {
}
