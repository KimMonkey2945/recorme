package com.recordapp.domain.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.user.dto.UpdateProfileRequest;
import com.recordapp.domain.user.dto.UserProfileResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import java.sql.Timestamp;
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
 * UserService 프로필 조회/수정 통합 테스트(Testcontainers PostgreSQL 18).
 * 조회·수정 정상, bio 빈문자열→NULL, 본인 외 미변경(IDOR), 부재 시 USER_NOT_FOUND를 검증한다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class UserServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	UserService userService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	/** JIT로 회원 1명 생성 후 내부 PK 반환. */
	private long provision(String sub, String email, Map<String, Object> metadata) {
		return provisioningService.provision(
				new SupabaseClaims(sub, email, metadata, Map.of("sub", sub))).userId();
	}

	@Test
	void getProfile_returnsJitProvisionedRow() {
		String sub = UUID.randomUUID().toString();
		long userId = provision(sub, "hong@example.com",
				Map.of("name", "홍길동", "avatar_url", "https://img/a.png"));

		UserProfileResponse profile = userService.getProfile(userId);

		assertThat(profile.nickname()).isEqualTo("홍길동");
		assertThat(profile.email()).isEqualTo("hong@example.com");
		assertThat(profile.profileImageUrl()).isEqualTo("https://img/a.png");
		assertThat(profile.bio()).isNull();
		assertThat(profile.uuid()).isNotBlank(); // 외부 노출 uuid(내부 PK 비노출)
	}

	@Test
	void getProfile_nonExistent_throwsUserNotFound() {
		assertThatThrownBy(() -> userService.getProfile(-1L))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.USER_NOT_FOUND));
	}

	@Test
	void updateProfile_updatesFieldsAndTimestamp() {
		String sub = UUID.randomUUID().toString();
		long userId = provision(sub, "u@example.com", Map.of("name", "old"));

		// updated_at 갱신을 결정적으로 검증하기 위해 과거로 백데이트
		jdbc().update("UPDATE users SET updated_at = now() - interval '1 hour' WHERE id = ?", userId);
		Timestamp before = jdbc().queryForObject(
				"SELECT updated_at FROM users WHERE id = ?", Timestamp.class, userId);

		UserProfileResponse updated = userService.updateProfile(userId,
				new UpdateProfileRequest("새닉네임", "https://img/new.png", "한 줄 소개"));

		assertThat(updated.nickname()).isEqualTo("새닉네임");
		assertThat(updated.profileImageUrl()).isEqualTo("https://img/new.png");
		assertThat(updated.bio()).isEqualTo("한 줄 소개");
		assertThat(updated.email()).isEqualTo("u@example.com"); // email은 수정 대상 아님

		Timestamp after = jdbc().queryForObject(
				"SELECT updated_at FROM users WHERE id = ?", Timestamp.class, userId);
		assertThat(after).isAfter(before);
	}

	@Test
	void updateProfile_blankBioAndImage_normalizedToNull() {
		String sub = UUID.randomUUID().toString();
		long userId = provision(sub, "b@example.com", Map.of("name", "n", "avatar_url", "https://img/x.png"));

		UserProfileResponse updated = userService.updateProfile(userId,
				new UpdateProfileRequest("닉", "   ", "  "));

		assertThat(updated.bio()).isNull();
		assertThat(updated.profileImageUrl()).isNull();

		Map<String, Object> row = jdbc().queryForMap(
				"SELECT bio, profile_image_url FROM users WHERE id = ?", userId);
		assertThat(row.get("bio")).isNull();
		assertThat(row.get("profile_image_url")).isNull();
	}

	@Test
	void updateProfile_doesNotAffectOtherUsers() {
		long victimId = provision(UUID.randomUUID().toString(), "victim@example.com", Map.of("name", "피해자"));
		long actorId = provision(UUID.randomUUID().toString(), "actor@example.com", Map.of("name", "행위자"));

		userService.updateProfile(actorId, new UpdateProfileRequest("변경됨", null, null));

		// 다른 사용자(victim) 행은 그대로여야 한다(소유권은 userId로만 식별 → IDOR 차단)
		UserProfileResponse victim = userService.getProfile(victimId);
		assertThat(victim.nickname()).isEqualTo("피해자");
	}

	@Test
	void updateProfile_nonExistent_throwsUserNotFound() {
		assertThatThrownBy(() -> userService.updateProfile(-1L,
				new UpdateProfileRequest("닉", null, null)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.USER_NOT_FOUND));
	}
}
