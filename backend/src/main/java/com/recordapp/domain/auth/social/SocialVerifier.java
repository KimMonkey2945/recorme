package com.recordapp.domain.auth.social;

/**
 * 소셜 토큰 검증 추상화. provider별 구현(KakaoVerifier/GoogleVerifier)을
 * SocialVerifierRouter가 provider 키로 라우팅한다.
 * (구현체는 Phase 3에서 추가.)
 */
public interface SocialVerifier {

	/** 이 검증기가 담당하는 제공자 */
	Provider provider();

	/** 소셜 토큰을 검증하고 사용자 정보를 추출. 실패 시 예외 */
	SocialUserInfo verify(String token);
}
