package com.recordapp.domain.auth.social;

/**
 * 소셜 로그인 제공자. 현재 검증 구현 범위는 KAKAO/GOOGLE.
 * APPLE은 social_accounts.provider에는 포함되나 검증 구현은 추후 확장.
 */
public enum Provider {
	KAKAO,
	GOOGLE
}
