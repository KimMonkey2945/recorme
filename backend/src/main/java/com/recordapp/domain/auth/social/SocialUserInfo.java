package com.recordapp.domain.auth.social;

/**
 * 소셜 제공자에서 검증·추출한 사용자 정보.
 * email/profileImageUrl은 제공자·동의 범위에 따라 null일 수 있다.
 */
public record SocialUserInfo(
		String providerUserId,
		String email,
		String nickname,
		String profileImageUrl) {
}
