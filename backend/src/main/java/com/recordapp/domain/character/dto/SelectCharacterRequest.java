package com.recordapp.domain.character.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 캐릭터 선택/교체 요청. 사용자 식별자는 바디에 두지 않는다(SecurityContext 의 userId 로만 식별 — IDOR 차단).
 * 없는/비활성 코드는 409 CHARACTER_NOT_OWNED.
 */
public record SelectCharacterRequest(
		@NotBlank String characterCode) {
}
