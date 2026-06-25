package com.recordapp.global.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jose.jwk.Curve;
import com.nimbusds.jose.jwk.ECKey;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.gen.ECKeyGenerator;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.JWSVerificationKeySelector;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.nimbusds.jwt.proc.DefaultJWTProcessor;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.Map;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

/**
 * SupabaseJwtVerifier 단위 테스트(Spring 컨텍스트·Docker·네트워크 불필요).
 * 인메모리 EC(P-256) 키페어를 만들어 그 공개키로 NimbusJwtDecoder를 주입하고,
 * 같은 개인키로 ES256 토큰을 직접 서명해 검증 동작을 확인한다.
 * 실제 Supabase JWKS endpoint는 호출하지 않는다.
 */
class SupabaseJwtVerifierTest {

	private static final String AUD = "authenticated";

	private static ECKey signingKey;   // 디코더가 신뢰하는 키(공개키가 JWKSet에 등록됨)
	private static ECKey foreignKey;   // 디코더가 모르는 키(위조 서명용)
	private static SupabaseJwtVerifier verifier;

	@BeforeAll
	static void setUp() throws Exception {
		signingKey = new ECKeyGenerator(Curve.P_256).keyID("test-kid").generate();
		foreignKey = new ECKeyGenerator(Curve.P_256).keyID("foreign-kid").generate();

		// 신뢰 키의 공개키만 담은 인메모리 JWKSet으로 ES256 디코더 구성
		JWKSource<SecurityContext> jwkSource =
				new ImmutableJWKSet<>(new JWKSet(signingKey.toPublicJWK()));
		DefaultJWTProcessor<SecurityContext> processor = new DefaultJWTProcessor<>();
		processor.setJWSKeySelector(new JWSVerificationKeySelector<>(JWSAlgorithm.ES256, jwkSource));
		// no-op: 만료 등 클레임 검증은 nimbus가 아닌 Spring validator(JwtTimestampValidator)로 위임(운영과 동일)
		processor.setJWTClaimsSetVerifier((claims, ctx) -> {
		});

		verifier = new SupabaseJwtVerifier(new NimbusJwtDecoder(processor));
	}

	@Test
	void verify_validToken_extractsClaims() throws Exception {
		String token = token(signingKey, AUD, Instant.now().plus(1, ChronoUnit.HOURS),
				"sub-uuid-1", "user@example.com", Map.of("name", "홍길동"));

		SupabaseClaims claims = verifier.verify(token);

		assertThat(claims.sub()).isEqualTo("sub-uuid-1");
		assertThat(claims.resolveEmail()).isEqualTo("user@example.com");
		assertThat(claims.resolveNickname()).isEqualTo("홍길동");
	}

	@Test
	void verify_forgedSignature_throwsInvalidToken() throws Exception {
		// 디코더가 모르는 키로 서명 → 서명 검증 실패
		String token = token(foreignKey, AUD, Instant.now().plus(1, ChronoUnit.HOURS),
				"sub", "e@x.com", null);

		assertErrorCode(() -> verifier.verify(token), ErrorCode.INVALID_TOKEN);
	}

	@Test
	void verify_tamperedToken_throwsInvalidToken() throws Exception {
		String token = token(signingKey, AUD, Instant.now().plus(1, ChronoUnit.HOURS),
				"sub", "e@x.com", null);
		String tampered = token.substring(0, token.length() - 2) + "xx";

		assertErrorCode(() -> verifier.verify(tampered), ErrorCode.INVALID_TOKEN);
	}

	@Test
	void verify_expiredToken_throwsExpiredToken() throws Exception {
		String token = token(signingKey, AUD, Instant.now().minus(1, ChronoUnit.MINUTES),
				"sub", "e@x.com", null);

		assertErrorCode(() -> verifier.verify(token), ErrorCode.EXPIRED_TOKEN);
	}

	@Test
	void verify_wrongAudience_throwsInvalidToken() throws Exception {
		String token = token(signingKey, "anon", Instant.now().plus(1, ChronoUnit.HOURS),
				"sub", "e@x.com", null);

		assertErrorCode(() -> verifier.verify(token), ErrorCode.INVALID_TOKEN);
	}

	@Test
	void verify_malformedToken_throwsBusinessException() {
		assertThatThrownBy(() -> verifier.verify("not-a-jwt"))
				.isInstanceOf(BusinessException.class);
	}

	// ----- helpers -----

	private void assertErrorCode(Runnable action, ErrorCode expected) {
		assertThatExceptionOfType(BusinessException.class)
				.isThrownBy(action::run)
				.satisfies(ex -> assertThat(ex.getErrorCode()).isEqualTo(expected));
	}

	/** EC 개인키로 ES256 서명한 토큰 직렬화. */
	private String token(ECKey ecKey, String aud, Instant exp,
			String sub, String email, Map<String, Object> metadata) throws Exception {
		JWTClaimsSet.Builder claims = new JWTClaimsSet.Builder()
				.subject(sub)
				.audience(aud)
				.expirationTime(Date.from(exp));
		if (email != null) {
			claims.claim("email", email);
		}
		if (metadata != null) {
			claims.claim("user_metadata", metadata);
		}
		SignedJWT jwt = new SignedJWT(
				new JWSHeader.Builder(JWSAlgorithm.ES256).keyID(ecKey.getKeyID()).build(),
				claims.build());
		jwt.sign(new ECDSASigner(ecKey));
		return jwt.serialize();
	}
}
