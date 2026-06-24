package com.recordapp.global.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.Test;

/**
 * JwtProvider 단위 테스트(Spring 컨텍스트·Docker 불필요).
 */
class JwtProviderTest {

	private static final String SECRET = "unit-test-secret-key-0123456789-abcdefghij";
	private final JwtProvider jwtProvider =
			new JwtProvider(new JwtProperties(SECRET, 1_800_000L, 1_209_600_000L));

	@Test
	void createAndParse_roundTrip() {
		String token = jwtProvider.createAccessToken(42L, "user-uuid-1");

		SecurityUser principal = jwtProvider.toPrincipal(jwtProvider.parse(token));

		assertThat(principal.userId()).isEqualTo(42L);
		assertThat(principal.uuid()).isEqualTo("user-uuid-1");
	}

	@Test
	void parse_rejectsTamperedToken() {
		String token = jwtProvider.createAccessToken(1L, "u");
		String tampered = token.substring(0, token.length() - 2) + "xx";

		assertThatThrownBy(() -> jwtProvider.parse(tampered))
				.isInstanceOf(JwtException.class);
	}

	@Test
	void parse_rejectsExpiredToken() {
		// 만료 시간 0ms → 즉시 만료
		JwtProvider shortLived = new JwtProvider(new JwtProperties(SECRET, 0L, 0L));
		String token = shortLived.createAccessToken(1L, "u");

		assertThatThrownBy(() -> shortLived.parse(token))
				.isInstanceOf(JwtException.class);
	}
}
