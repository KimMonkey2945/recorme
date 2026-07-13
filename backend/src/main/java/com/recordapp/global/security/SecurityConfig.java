package com.recordapp.global.security;

import java.util.List;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * STATELESS 보안 설정. 인증은 Supabase access token 검증 + JIT 프로비저닝으로 처리한다.
 * 컨텍스트 경로(/api/v1) 하위 기준으로 공유 링크 조회만 비인증 허용, 그 외는 인증 필요.
 * (자체 로그인/토큰 발급이 없으므로 /auth/** permitAll 없음.)
 * 401은 JwtAuthenticationEntryPoint가 표준 JSON으로 응답한다.
 */
@Configuration
@EnableWebSecurity
@EnableConfigurationProperties(SupabaseProperties.class)
public class SecurityConfig {

	private final SupabaseJwtFilter supabaseJwtFilter;
	private final RateLimitFilter rateLimitFilter;
	private final JwtAuthenticationEntryPoint authenticationEntryPoint;

	public SecurityConfig(SupabaseJwtFilter supabaseJwtFilter,
			RateLimitFilter rateLimitFilter,
			JwtAuthenticationEntryPoint authenticationEntryPoint) {
		this.supabaseJwtFilter = supabaseJwtFilter;
		this.rateLimitFilter = rateLimitFilter;
		this.authenticationEntryPoint = authenticationEntryPoint;
	}

	@Bean
	public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
		http
				.cors(Customizer.withDefaults())
				.csrf(AbstractHttpConfigurer::disable)
				.httpBasic(AbstractHttpConfigurer::disable)
				.formLogin(AbstractHttpConfigurer::disable)
				.logout(AbstractHttpConfigurer::disable)
				.sessionManagement(session ->
						session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
				.authorizeHttpRequests(auth -> auth
						.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()  // CORS preflight
						.requestMatchers(HttpMethod.GET, "/auth/email-exists").permitAll()  // 비번찾기 미가입 사전 안내(비로그인)
						.requestMatchers(HttpMethod.GET, "/diaries/shared/**").permitAll()
						.requestMatchers(HttpMethod.GET, "/files/**").permitAll()  // 업로드 이미지 공개 서빙(UUID 파일명)
						.anyRequest().authenticated())
				.exceptionHandling(handler ->
						handler.authenticationEntryPoint(authenticationEntryPoint))
				.addFilterBefore(supabaseJwtFilter, UsernamePasswordAuthenticationFilter.class)
				// rate limit 은 인증 이후(userId 식별 가능)·인가 이전에 수행 — 남용/DoS/열거 1차 차단.
				.addFilterAfter(rateLimitFilter, SupabaseJwtFilter.class);
		return http.build();
	}

	/**
	 * 개발용 CORS. 로컬 웹(Flutter web 등) origin만 허용한다.
	 * 운영 origin은 추후 cloud 프로파일에서 별도로 좁힌다.
	 */
	@Bean
	public CorsConfigurationSource corsConfigurationSource() {
		CorsConfiguration config = new CorsConfiguration();
		config.setAllowedOriginPatterns(List.of("http://localhost:*", "http://127.0.0.1:*"));
		config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
		config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
		config.setAllowCredentials(true);
		UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
		source.registerCorsConfiguration("/**", config);
		return source;
	}
}
