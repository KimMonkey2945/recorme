package com.recordapp.domain.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.user.dto.UpdateProfileRequest;
import com.recordapp.domain.user.dto.UserProfileResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import com.recordapp.infra.storage.StorageProperties;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Timestamp;
import java.util.Map;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.multipart.MultipartFile;
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

	@Autowired
	StorageProperties storageProperties;

	/** 저장 URL(상대경로 /files/...)을 디스크 실제 경로로 환산. */
	private Path resolveStored(String url) {
		String urlPath = storageProperties.urlPath(); // "/files"
		String relative = url.substring(urlPath.length() + 1); // urlPath + "/" 제거
		return Paths.get(storageProperties.root()).toAbsolutePath().normalize().resolve(relative);
	}

	/** 유효한 PNG 매직바이트로 시작하는 가짜 이미지. */
	private MockMultipartFile pngFile() {
		byte[] png = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0};
		return new MockMultipartFile("file", "a.png", MediaType.IMAGE_PNG_VALUE, png);
	}

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
				new UpdateProfileRequest("새닉네임", "한 줄 소개"));

		assertThat(updated.nickname()).isEqualTo("새닉네임");
		assertThat(updated.bio()).isEqualTo("한 줄 소개");
		assertThat(updated.email()).isEqualTo("u@example.com"); // email은 수정 대상 아님

		Timestamp after = jdbc().queryForObject(
				"SELECT updated_at FROM users WHERE id = ?", Timestamp.class, userId);
		assertThat(after).isAfter(before);
	}

	@Test
	void updateProfile_blankBio_normalizedToNull_andImagePreserved() {
		String sub = UUID.randomUUID().toString();
		long userId = provision(sub, "b@example.com", Map.of("name", "n", "avatar_url", "https://img/x.png"));

		UserProfileResponse updated = userService.updateProfile(userId,
				new UpdateProfileRequest("닉", "  "));

		assertThat(updated.bio()).isNull();
		// 분리 회귀: 닉네임/bio 수정이 프로필 이미지를 덮어쓰지 않는다(JIT 아바타 유지).
		assertThat(updated.profileImageUrl()).isEqualTo("https://img/x.png");

		Map<String, Object> row = jdbc().queryForMap(
				"SELECT bio, profile_image_url FROM users WHERE id = ?", userId);
		assertThat(row.get("bio")).isNull();
		assertThat(row.get("profile_image_url")).isEqualTo("https://img/x.png");
	}

	@Test
	void updateProfile_doesNotAffectOtherUsers() {
		long victimId = provision(UUID.randomUUID().toString(), "victim@example.com", Map.of("name", "피해자"));
		long actorId = provision(UUID.randomUUID().toString(), "actor@example.com", Map.of("name", "행위자"));

		userService.updateProfile(actorId, new UpdateProfileRequest("변경됨", null));

		// 다른 사용자(victim) 행은 그대로여야 한다(소유권은 userId로만 식별 → IDOR 차단)
		UserProfileResponse victim = userService.getProfile(victimId);
		assertThat(victim.nickname()).isEqualTo("피해자");
	}

	@Test
	void updateProfile_nonExistent_throwsUserNotFound() {
		assertThatThrownBy(() -> userService.updateProfile(-1L,
				new UpdateProfileRequest("닉", null)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.USER_NOT_FOUND));
	}

	// ===== 프로필 이미지 업로드(updateAvatar) =====

	@Test
	void updateAvatar_storesFileAndUpdatesPath() throws Exception {
		long userId = provision(UUID.randomUUID().toString(), "av@example.com", Map.of("name", "아바타"));

		UserProfileResponse updated = userService.updateAvatar(userId, pngFile());

		assertThat(updated.profileImageUrl()).startsWith("/files/avatars/").endsWith(".png");
		assertThat(Files.exists(resolveStored(updated.profileImageUrl()))).isTrue();
		// DB에도 경로가 저장됐는지 확인
		String dbUrl = jdbc().queryForObject(
				"SELECT profile_image_url FROM users WHERE id = ?", String.class, userId);
		assertThat(dbUrl).isEqualTo(updated.profileImageUrl());
	}

	@Test
	void updateAvatar_replacesOldFileOnReupload() throws Exception {
		long userId = provision(UUID.randomUUID().toString(), "re@example.com", Map.of("name", "재업로드"));

		String firstUrl = userService.updateAvatar(userId, pngFile()).profileImageUrl();
		Path firstPath = resolveStored(firstUrl);
		assertThat(Files.exists(firstPath)).isTrue();

		String secondUrl = userService.updateAvatar(userId, pngFile()).profileImageUrl();

		assertThat(secondUrl).isNotEqualTo(firstUrl);
		assertThat(Files.exists(resolveStored(secondUrl))).isTrue();
		assertThat(Files.exists(firstPath)).as("구 파일은 삭제되어야 한다").isFalse();
	}

	@Test
	void updateAvatar_invalidContent_throwsInvalidFileAndKeepsOldImage() {
		long userId = provision(UUID.randomUUID().toString(), "bad@example.com",
				Map.of("name", "n", "avatar_url", "https://img/keep.png"));
		MultipartFile notImage = new MockMultipartFile(
				"file", "a.txt", MediaType.TEXT_PLAIN_VALUE, "hello".getBytes());

		assertThatThrownBy(() -> userService.updateAvatar(userId, notImage))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.INVALID_FILE));

		// 검증 실패 시 기존 이미지(외부 URL)는 그대로 유지
		assertThat(userService.getProfile(userId).profileImageUrl()).isEqualTo("https://img/keep.png");
	}

	@Test
	void updateAvatar_externalUrlOwner_uploadsAndNoOpDeletesExternal() throws Exception {
		// 기존 값이 외부 URL이어도 deleteByUrl이 no-op → 예외 없이 새 파일로 교체된다.
		long userId = provision(UUID.randomUUID().toString(), "ext@example.com",
				Map.of("name", "n", "avatar_url", "https://external/cdn/p.png"));

		UserProfileResponse updated = userService.updateAvatar(userId, pngFile());

		assertThat(updated.profileImageUrl()).startsWith("/files/avatars/");
		assertThat(Files.exists(resolveStored(updated.profileImageUrl()))).isTrue();
	}
}
