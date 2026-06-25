package com.recordapp.domain.auth.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.recordapp.global.security.SecurityUser;
import com.recordapp.global.security.SupabaseClaims;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * UserProvisioningService JIT 프로비저닝 통합 테스트(Testcontainers PostgreSQL).
 * 신규 가입(폴백), 기존 매핑(중복 없음), 동시 최초요청 race-safe, 이메일 가입 토큰 형태를 검증한다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class UserProvisioningServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	private SupabaseClaims claims(String sub, String email, Map<String, Object> metadata) {
		return new SupabaseClaims(sub, email, metadata, Map.of("sub", sub));
	}

	private int countBySub(String sub) {
		return jdbc().queryForObject(
				"SELECT count(*) FROM users WHERE supabase_uid = ?::uuid", Integer.class, sub);
	}

	private Map<String, Object> row(long id) {
		return jdbc().queryForMap(
				"SELECT nickname, email, profile_image_url, supabase_uid::text AS supabase_uid "
						+ "FROM users WHERE id = ?", id);
	}

	@Test
	void newSignup_jit_fillsNicknameAvatarEmail() {
		String sub = UUID.randomUUID().toString();
		SupabaseClaims claims = claims(sub, "hong@example.com",
				Map.of("name", "홍길동", "avatar_url", "https://img/a.png"));

		SecurityUser user = provisioningService.provision(claims);

		assertThat(user.userId()).isNotNull();
		assertThat(user.supabaseUuid()).isEqualTo(sub);
		Map<String, Object> row = row(user.userId());
		assertThat(row.get("nickname")).isEqualTo("홍길동");
		assertThat(row.get("email")).isEqualTo("hong@example.com");
		assertThat(row.get("profile_image_url")).isEqualTo("https://img/a.png");
		assertThat(row.get("supabase_uid")).isEqualTo(sub);
	}

	@Test
	void newSignup_nicknameFallback_fullName() {
		String sub = UUID.randomUUID().toString();
		SecurityUser user = provisioningService.provision(
				claims(sub, null, Map.of("full_name", "전체이름")));
		assertThat(row(user.userId()).get("nickname")).isEqualTo("전체이름");
	}

	@Test
	void newSignup_nicknameFallback_userName() {
		String sub = UUID.randomUUID().toString();
		SecurityUser user = provisioningService.provision(
				claims(sub, null, Map.of("user_name", "유저네임")));
		assertThat(row(user.userId()).get("nickname")).isEqualTo("유저네임");
	}

	@Test
	void newSignup_nicknameFallback_emailLocalPart() {
		String sub = UUID.randomUUID().toString();
		SecurityUser user = provisioningService.provision(
				claims(sub, "localpart@example.com", Map.of()));
		assertThat(row(user.userId()).get("nickname")).isEqualTo("localpart");
	}

	@Test
	void newSignup_nicknameFallback_default() {
		String sub = UUID.randomUUID().toString();
		SecurityUser user = provisioningService.provision(claims(sub, null, null));
		assertThat(row(user.userId()).get("nickname")).isEqualTo("user");
	}

	@Test
	void emailSignupToken_form_provisionsSamePath() {
		// 이메일 가입: top-level email만 있고 name 류 메타데이터 없음 → 동일 경로로 가입
		String sub = UUID.randomUUID().toString();
		SecurityUser user = provisioningService.provision(
				claims(sub, "mailer@example.com", Map.of("email", "mailer@example.com")));

		Map<String, Object> row = row(user.userId());
		assertThat(row.get("nickname")).isEqualTo("mailer");
		assertThat(row.get("email")).isEqualTo("mailer@example.com");
		assertThat(row.get("profile_image_url")).isNull();
	}

	@Test
	void existingUser_mapsToSameRow_noDuplicate() {
		String sub = UUID.randomUUID().toString();
		SecurityUser first = provisioningService.provision(claims(sub, "dup@example.com", Map.of("name", "A")));
		SecurityUser second = provisioningService.provision(claims(sub, "dup@example.com", Map.of("name", "A")));

		assertThat(second.userId()).isEqualTo(first.userId());
		assertThat(countBySub(sub)).isEqualTo(1);
	}

	@Test
	void concurrentFirstRequests_areRaceSafe_singleRow() throws Exception {
		String sub = UUID.randomUUID().toString();
		SupabaseClaims claims = claims(sub, "race@example.com", Map.of("name", "동시"));

		int threads = 2;
		CyclicBarrier barrier = new CyclicBarrier(threads);
		ExecutorService pool = Executors.newFixedThreadPool(threads);
		try {
			Callable<Long> task = () -> {
				barrier.await(); // 두 스레드를 동시에 출발시켜 경합 유도
				return provisioningService.provision(claims).userId();
			};
			Future<Long> f1 = pool.submit(task);
			Future<Long> f2 = pool.submit(task);

			Long id1 = f1.get();
			Long id2 = f2.get();

			assertThat(id1).isEqualTo(id2);
			assertThat(countBySub(sub)).isEqualTo(1);
		} finally {
			pool.shutdownNow();
		}
	}
}
