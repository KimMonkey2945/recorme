package com.recordapp.global.security;

import java.util.List;
import java.util.Map;

/**
 * 검증된 Supabase access token에서 추출한 클레임.
 * 이메일·소셜 가입 모두 동일 형식이라 provider를 구분하지 않는다.
 *
 * <p>닉네임/아바타/이메일은 top-level 클레임과 {@code user_metadata}를 폴백 순서대로 조회한다.
 * (소셜은 user_metadata에 name/avatar_url 등을 담고, 이메일 가입은 email만 있을 수 있다.)
 *
 * @param sub          Supabase user uuid(JWT subject). users.supabase_uid 매핑 키
 * @param email        top-level email 클레임(nullable)
 * @param userMetadata user_metadata 클레임 맵(nullable)
 * @param claims       전체 페이로드(top-level 폴백 조회용)
 */
public record SupabaseClaims(
		String sub,
		String email,
		Map<String, Object> userMetadata,
		Map<String, Object> claims) {

	private static final List<String> NICKNAME_KEYS =
			List.of("name", "full_name", "nickname", "user_name");
	private static final List<String> AVATAR_KEYS =
			List.of("avatar_url", "picture");
	private static final String NICKNAME_DEFAULT = "user";

	/** 닉네임 폴백: name → full_name → nickname → user_name → email local-part → "user" */
	public String resolveNickname() {
		for (String key : NICKNAME_KEYS) {
			String value = pick(key);
			if (value != null) {
				return value;
			}
		}
		String resolvedEmail = resolveEmail();
		if (resolvedEmail != null) {
			int at = resolvedEmail.indexOf('@');
			if (at > 0) {
				return resolvedEmail.substring(0, at);
			}
		}
		return NICKNAME_DEFAULT;
	}

	/** 아바타 폴백: avatar_url → picture (없으면 null) */
	public String resolveAvatarUrl() {
		for (String key : AVATAR_KEYS) {
			String value = pick(key);
			if (value != null) {
				return value;
			}
		}
		return null;
	}

	/** 이메일 폴백: top-level email → user_metadata.email (없으면 null) */
	public String resolveEmail() {
		if (email != null && !email.isBlank()) {
			return email;
		}
		return pick("email");
	}

	/** user_metadata 우선, 없으면 top-level 클레임에서 문자열 값을 조회(공백·비문자열은 무시) */
	private String pick(String key) {
		Object value = (userMetadata != null) ? userMetadata.get(key) : null;
		if (value == null && claims != null) {
			value = claims.get(key);
		}
		return (value instanceof String s && !s.isBlank()) ? s : null;
	}
}
