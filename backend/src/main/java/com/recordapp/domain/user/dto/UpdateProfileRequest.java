package com.recordapp.domain.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 프로필 수정 요청. nickname 필수, bio 선택(nullable).
 * email은 Supabase 소유라 수정 대상이 아니다(요청 바디에 없음).
 * 프로필 이미지는 이 경로에서 다루지 않는다 — 별도 업로드 엔드포인트(POST /users/me/avatar)에서만
 * 갱신하므로 닉네임·자기소개 수정이 이미지를 덮어쓰지 않는다.
 * 소유권은 SecurityContext의 userId로만 식별하므로 바디에 id를 두지 않는다(IDOR 차단).
 */
public record UpdateProfileRequest(
		@NotBlank @Size(max = 50) String nickname,
		@Size(max = 300) String bio) {
}
