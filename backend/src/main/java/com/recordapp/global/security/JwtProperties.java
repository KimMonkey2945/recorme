package com.recordapp.global.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * JWT 설정(record.jwt.*). 시크릿은 환경변수/시크릿으로 주입한다.
 */
@ConfigurationProperties(prefix = "record.jwt")
public record JwtProperties(
		String secret,
		long accessExpirationMs,
		long refreshExpirationMs) {
}
