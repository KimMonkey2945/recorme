package com.recordapp.domain.user.dto;

/**
 * 프로필 조회/수정 응답. 외부 노출 식별자는 내부 PK가 아닌 uuid를 사용한다.
 * email은 Supabase 소유라 조회 전용(수정 불가).
 */
public record UserProfileResponse(
		String uuid,
		String nickname,
		String email,
		String profileImageUrl,
		String bio) {
}
