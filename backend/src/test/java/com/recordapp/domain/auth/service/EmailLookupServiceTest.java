package com.recordapp.domain.auth.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.recordapp.global.security.SupabaseClaims;
import java.util.Map;
import java.util.UUID;
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
 * EmailLookupService 통합 테스트(Testcontainers PostgreSQL 18).
 * 가입/미가입/대소문자 무시/소프트삭제/빈 값 경계를 검증한다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class EmailLookupServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	EmailLookupService emailLookupService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	/** JIT로 회원 1명 생성 후 내부 PK 반환. */
	private long provision(String sub, String email) {
		return provisioningService.provision(
				new SupabaseClaims(sub, email, Map.of("name", "tester"), Map.of("sub", sub))).userId();
	}

	@Test
	void registeredEmail_returnsTrue() {
		provision(UUID.randomUUID().toString(), "hong@example.com");

		assertThat(emailLookupService.isEmailRegistered("hong@example.com")).isTrue();
	}

	@Test
	void unregisteredEmail_returnsFalse() {
		assertThat(emailLookupService.isEmailRegistered("nobody@example.com")).isFalse();
	}

	@Test
	void caseInsensitive_returnsTrue() {
		provision(UUID.randomUUID().toString(), "Mixed.Case@Example.com");

		assertThat(emailLookupService.isEmailRegistered("mixed.case@example.com")).isTrue();
	}

	@Test
	void softDeletedUser_returnsFalse() {
		String sub = UUID.randomUUID().toString();
		long userId = provision(sub, "left@example.com");
		jdbc().update("UPDATE users SET deleted_at = now() WHERE id = ?", userId);

		assertThat(emailLookupService.isEmailRegistered("left@example.com")).isFalse();
	}

	@Test
	void blankEmail_returnsFalse() {
		assertThat(emailLookupService.isEmailRegistered("   ")).isFalse();
		assertThat(emailLookupService.isEmailRegistered("")).isFalse();
		assertThat(emailLookupService.isEmailRegistered(null)).isFalse();
	}
}
