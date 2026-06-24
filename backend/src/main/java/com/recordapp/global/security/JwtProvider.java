package com.recordapp.global.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jws;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.stereotype.Component;

/**
 * JWT access 토큰 발급/검증.
 * refresh 토큰은 JWT가 아닌 랜덤 문자열을 SHA-256 해시로 저장하므로(Phase 3 TokenService),
 * 여기서는 access 토큰만 다룬다.
 */
@Component
public class JwtProvider {

	private static final String CLAIM_UUID = "uuid";

	private final SecretKey key;
	private final long accessExpirationMs;

	public JwtProvider(JwtProperties properties) {
		this.key = Keys.hmacShaKeyFor(properties.secret().getBytes(StandardCharsets.UTF_8));
		this.accessExpirationMs = properties.accessExpirationMs();
	}

	/** access 토큰 발급: subject=userId, claim uuid=외부 식별자 */
	public String createAccessToken(long userId, String uuid) {
		Instant now = Instant.now();
		return Jwts.builder()
				.subject(String.valueOf(userId))
				.claim(CLAIM_UUID, uuid)
				.issuedAt(Date.from(now))
				.expiration(Date.from(now.plusMillis(accessExpirationMs)))
				.signWith(key)
				.compact();
	}

	/** 서명·만료 검증 후 클레임 반환. 실패 시 io.jsonwebtoken 예외 throw */
	public Jws<Claims> parse(String token) {
		return Jwts.parser()
				.verifyWith(key)
				.build()
				.parseSignedClaims(token);
	}

	/** 검증된 토큰에서 SecurityUser 추출 */
	public SecurityUser toPrincipal(Jws<Claims> jws) {
		Claims claims = jws.getPayload();
		long userId = Long.parseLong(claims.getSubject());
		String uuid = claims.get(CLAIM_UUID, String.class);
		return new SecurityUser(userId, uuid);
	}
}
