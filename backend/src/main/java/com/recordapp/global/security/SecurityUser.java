package com.recordapp.global.security;

/**
 * 인증된 사용자 principal.
 * Supabase JWT 검증 + JIT 프로비저닝으로 확보한 내부 식별자를 담는다.
 * Controller에서 {@code @AuthenticationPrincipal SecurityUser}로 주입받아 본인 식별에 사용한다.
 *
 * @param userId       내부 PK(users.id, BIGINT)
 * @param supabaseUuid Supabase user uuid(JWT sub, users.supabase_uid)
 */
public record SecurityUser(Long userId, String supabaseUuid) {
}
