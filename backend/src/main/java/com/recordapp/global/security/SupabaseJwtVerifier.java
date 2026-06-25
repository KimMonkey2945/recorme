package com.recordapp.global.security;

import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtValidationException;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Component;

/**
 * Supabase access token(ES256) 검증기.
 * 프로젝트 JWKS로 서명을 검증하고, 만료·aud("authenticated")를 확인한 뒤 {@link SupabaseClaims}를 추출한다.
 * 자체 토큰 발급은 하지 않는다(검증 전용). NimbusJwtDecoder가 JWKS fetch·캐싱·키회전을 처리한다.
 */
@Component
public class SupabaseJwtVerifier {

	/** Supabase access token의 고정 audience */
	private static final String AUDIENCE = "authenticated";

	private final JwtDecoder decoder;

	@Autowired
	public SupabaseJwtVerifier(SupabaseProperties properties) {
		// 기본 알고리즘은 RS256 → ES256 명시 필수(누락 시 Supabase ES256 토큰 전부 INVALID).
		// withJwkSetUri는 lazy: 빈 생성·기동엔 네트워크 불필요, 첫 검증 때 JWKS fetch.
		this(NimbusJwtDecoder.withJwkSetUri(properties.jwksUri())
				.jwsAlgorithm(SignatureAlgorithm.ES256)
				.build());
	}

	/** 테스트 주입용(인메모리 EC 공개키 기반 NimbusJwtDecoder). validator는 여기서 공통 적용. */
	SupabaseJwtVerifier(NimbusJwtDecoder decoder) {
		decoder.setJwtValidator(buildValidator());
		this.decoder = decoder;
	}

	/** 기본 검증기(만료 등) + audience("authenticated") 검증 조합. */
	private static OAuth2TokenValidator<Jwt> buildValidator() {
		OAuth2TokenValidator<Jwt> audience = jwt ->
				jwt.getAudience() != null && jwt.getAudience().contains(AUDIENCE)
						? OAuth2TokenValidatorResult.success()
						: OAuth2TokenValidatorResult.failure(new OAuth2Error(
								"invalid_token", "Required audience [" + AUDIENCE + "] is missing", null));
		return new DelegatingOAuth2TokenValidator<>(JwtValidators.createDefault(), audience);
	}

	/**
	 * 토큰을 검증하고 클레임을 추출한다.
	 *
	 * @throws BusinessException EXPIRED_TOKEN(만료) / INVALID_TOKEN(서명·aud·형식·JWKS 조회 오류)
	 */
	public SupabaseClaims verify(String token) {
		try {
			Jwt jwt = decoder.decode(token);
			return new SupabaseClaims(
					jwt.getSubject(),
					jwt.getClaimAsString("email"),
					jwt.getClaimAsMap("user_metadata"),
					jwt.getClaims());
		} catch (JwtValidationException e) {
			// 서명 검증 후 validator 단계 실패(만료·aud 등). 만료만 EXPIRED로 분기.
			boolean expired = e.getErrors().stream()
					.anyMatch(err -> err.getDescription() != null
							&& err.getDescription().toLowerCase().contains("expired"));
			throw new BusinessException(expired ? ErrorCode.EXPIRED_TOKEN : ErrorCode.INVALID_TOKEN);
		} catch (JwtException e) {
			// 서명 불일치 / 형식 오류 / JWKS 조회 실패 등
			throw new BusinessException(ErrorCode.INVALID_TOKEN);
		}
	}
}
