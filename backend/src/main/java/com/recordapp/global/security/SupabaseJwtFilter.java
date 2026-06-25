package com.recordapp.global.security;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.global.exception.BusinessException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Authorization: Bearer 의 Supabase access token을 검증하고,
 * JIT 프로비저닝으로 확보한 {@link SecurityUser}를 SecurityContext에 세팅한다.
 *
 * <p>토큰이 없으면 그대로 통과시킨다(보호 자원 접근은 EntryPoint가 401 처리).
 * 검증·프로비저닝 실패 시 인증을 세팅하지 않아 EntryPoint가 401을 응답한다.
 */
@Component
public class SupabaseJwtFilter extends OncePerRequestFilter {

	private static final String BEARER_PREFIX = "Bearer ";

	private final SupabaseJwtVerifier verifier;
	private final UserProvisioningService provisioningService;

	public SupabaseJwtFilter(SupabaseJwtVerifier verifier,
			UserProvisioningService provisioningService) {
		this.verifier = verifier;
		this.provisioningService = provisioningService;
	}

	@Override
	protected void doFilterInternal(@NonNull HttpServletRequest request,
			@NonNull HttpServletResponse response,
			@NonNull FilterChain filterChain) throws ServletException, IOException {

		String token = resolveToken(request);
		if (token != null) {
			try {
				SupabaseClaims claims = verifier.verify(token);
				SecurityUser principal = provisioningService.provision(claims);
				var authentication = new UsernamePasswordAuthenticationToken(
						principal, null, List.of());
				SecurityContextHolder.getContext().setAuthentication(authentication);
			} catch (BusinessException e) {
				// 검증·프로비저닝 실패 → 인증 미설정(이후 EntryPoint가 401 처리)
				SecurityContextHolder.clearContext();
			}
		}
		filterChain.doFilter(request, response);
	}

	private String resolveToken(HttpServletRequest request) {
		String header = request.getHeader("Authorization");
		if (header != null && header.startsWith(BEARER_PREFIX)) {
			return header.substring(BEARER_PREFIX.length());
		}
		return null;
	}
}
