package com.recordapp.global.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Supabase 인증 설정(supabase.*). 백엔드는 자체 JWT를 발급하지 않고
 * Supabase가 ES256로 서명한 access token을 JWKS로 검증만 한다.
 *
 * @param url Supabase 프로젝트 URL(예: https://&lt;ref&gt;.supabase.co). 환경변수로 주입.
 */
@ConfigurationProperties(prefix = "supabase")
public record SupabaseProperties(String url) {

	/** JWKS endpoint = url + /auth/v1/.well-known/jwks.json (트레일링 슬래시 방어). */
	public String jwksUri() {
		String base = (url != null && url.endsWith("/")) ? url.substring(0, url.length() - 1) : url;
		return base + "/auth/v1/.well-known/jwks.json";
	}
}
