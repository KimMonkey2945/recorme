package com.recordapp.domain.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.hibernate.validator.constraints.URL;

/**
 * 프로필 수정 요청. nickname 필수, 나머지 선택(nullable).
 * email은 Supabase 소유라 수정 대상이 아니다(요청 바디에 없음).
 * 소유권은 SecurityContext의 userId로만 식별하므로 바디에 id를 두지 않는다(IDOR 차단).
 */
public record UpdateProfileRequest(
		@NotBlank @Size(max = 50) String nickname,
		@URL @Size(max = 2048) String profileImageUrl,
		@Size(max = 300) String bio) {
}
