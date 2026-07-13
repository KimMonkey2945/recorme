package com.recordapp.global.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.exception.ErrorCode;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 공개 인터넷 노출(Tailscale Funnel) 대비 애플리케이션 레벨 rate limiting.
 * Funnel 은 TLS 종단만 하고 rate limit/WAF 가 없으므로, 남용·DoS·이메일 열거·LLM 비용 폭주를
 * 여기서 1차 방어한다. 인메모리 토큰 버킷(홈서버 단일 인스턴스 전제 — LocalDiskStorageService 와 동일).
 *
 * <p>{@link SupabaseJwtFilter} 다음에 등록되어(SecurityConfig) 인증된 요청은 userId 로,
 * 그 외에는 클라이언트 IP 로 버킷을 나눈다. 대상:
 * <ul>
 *   <li>무인증 공개 GET({@code /auth/email-exists}, {@code /diaries/shared/**}, {@code /files/**}) → IP 당 30 req/min
 *   <li>쓰기({@code POST /diaries}, 확정 시 LLM 트리거) → userId(없으면 IP) 당 10 req/min
 * </ul>
 * 초과 시 표준 래퍼로 429(RATE_LIMITED)를 반환한다. 그 외 경로는 제한하지 않는다(정상 사용 영향 최소화).
 */
@Component
public class RateLimitFilter extends OncePerRequestFilter {

	/** 무인증 공개 조회 한도(분당). */
	private static final int PUBLIC_CAPACITY = 30;
	/** 쓰기(LLM 트리거 포함) 한도(분당). */
	private static final int WRITE_CAPACITY = 10;
	private static final long WINDOW_NANOS = 60L * 1_000_000_000L;
	/** 버킷 맵 무한 증가 방지 상한(초과 시 초기화 — 홈서버 소규모 전제의 단순 방어). */
	private static final int MAX_BUCKETS = 50_000;

	private final ObjectMapper objectMapper;
	private final ConcurrentHashMap<String, TokenBucket> buckets = new ConcurrentHashMap<>();

	public RateLimitFilter(ObjectMapper objectMapper) {
		this.objectMapper = objectMapper;
	}

	@Override
	protected void doFilterInternal(@NonNull HttpServletRequest request,
			@NonNull HttpServletResponse response,
			@NonNull FilterChain filterChain) throws ServletException, IOException {

		String path = pathWithinApp(request);
		String method = request.getMethod();

		String key = null;
		int capacity = 0;
		if (HttpMethod.GET.matches(method) && isPublicEndpoint(path)) {
			key = "pub:" + clientIp(request);
			capacity = PUBLIC_CAPACITY;
		} else if (HttpMethod.POST.matches(method) && "/diaries".equals(path)) {
			key = "wr:" + writeIdentity(request);
			capacity = WRITE_CAPACITY;
		}

		if (key != null && !tryConsume(key, capacity)) {
			writeTooManyRequests(response);
			return;
		}
		filterChain.doFilter(request, response);
	}

	private boolean isPublicEndpoint(String path) {
		return "/auth/email-exists".equals(path)
				|| path.startsWith("/diaries/shared/")
				|| path.startsWith("/files/");
	}

	/** 컨텍스트 경로(/api/v1)를 제거한 애플리케이션 내부 경로. */
	private String pathWithinApp(HttpServletRequest request) {
		String uri = request.getRequestURI();
		String ctx = request.getContextPath();
		if (ctx != null && !ctx.isEmpty() && uri.startsWith(ctx)) {
			return uri.substring(ctx.length());
		}
		return uri;
	}

	/** 인증되어 있으면 userId, 아니면 IP 로 쓰기 버킷을 나눈다. */
	private String writeIdentity(HttpServletRequest request) {
		Authentication auth = SecurityContextHolder.getContext().getAuthentication();
		if (auth != null && auth.getPrincipal() instanceof SecurityUser user) {
			return "user:" + user.userId();
		}
		return "ip:" + clientIp(request);
	}

	/**
	 * 클라이언트 IP. Funnel/프록시 경유이므로 X-Forwarded-For 첫 홉을 우선 신뢰한다.
	 * (백엔드는 신뢰된 프록시(Funnel/로컬) 뒤에만 두는 것을 전제로 한다 — 직접 노출 금지.)
	 */
	private String clientIp(HttpServletRequest request) {
		String xff = request.getHeader("X-Forwarded-For");
		if (xff != null && !xff.isBlank()) {
			int comma = xff.indexOf(',');
			return (comma > 0 ? xff.substring(0, comma) : xff).trim();
		}
		return request.getRemoteAddr();
	}

	private boolean tryConsume(String key, int capacity) {
		if (buckets.size() > MAX_BUCKETS) {
			buckets.clear();
		}
		TokenBucket bucket = buckets.computeIfAbsent(key, k -> new TokenBucket(capacity));
		return bucket.tryConsume();
	}

	private void writeTooManyRequests(HttpServletResponse response) throws IOException {
		response.setStatus(ErrorCode.RATE_LIMITED.getStatus().value());
		response.setContentType(MediaType.APPLICATION_JSON_VALUE);
		response.setCharacterEncoding(StandardCharsets.UTF_8.name());
		objectMapper.writeValue(response.getWriter(), ApiResponse.fail(ErrorCode.RATE_LIMITED));
	}

	/** 단순 토큰 버킷(capacity 개/분, 연속 리필). 키별 1개 인스턴스라 인스턴스 단위 동기화로 충분하다. */
	private static final class TokenBucket {

		private final double capacity;
		private final double refillPerNano;
		private double tokens;
		private long lastNanos;

		TokenBucket(int capacity) {
			this.capacity = capacity;
			this.refillPerNano = (double) capacity / WINDOW_NANOS;
			this.tokens = capacity;
			this.lastNanos = System.nanoTime();
		}

		synchronized boolean tryConsume() {
			long now = System.nanoTime();
			tokens = Math.min(capacity, tokens + (now - lastNanos) * refillPerNano);
			lastNanos = now;
			if (tokens >= 1.0) {
				tokens -= 1.0;
				return true;
			}
			return false;
		}
	}
}
