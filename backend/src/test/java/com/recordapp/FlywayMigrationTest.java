package com.recordapp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.flywaydb.core.Flyway;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Flyway V1(users) 마이그레이션과 회원 스키마 제약을 Testcontainers PostgreSQL로 검증한다.
 *  (a) 마이그레이션 무오류 적용 + users 테이블 생성 + uq_users_email_active 부분 유니크 인덱스
 *  (b) uq_users_supabase_uid: 같은 supabase_uid 중복 INSERT → 유니크 제약 위반
 *  (c) uq_users_email_active: 같은 lower(email) 활성 중복 거부 /
 *      email NULL 다중 행 허용 / 소프트 삭제 후 같은 email 재INSERT 허용
 *
 * diaries(부분 유니크·upsert·소프트삭제 재작성) 검증은 V2__add_diaries.sql(Task 008)에서
 * 별도 테스트로 복원한다 — diaries 가 V1에서 빠졌으므로 본 클래스에서 제거.
 *
 * 이미지는 운영 DB(PostgreSQL 18, recorme)와 일치시키기 위해 postgres:18-alpine 사용.
 */
@Testcontainers
class FlywayMigrationTest {

	@Container
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@BeforeAll
	static void migrate() {
		Flyway.configure()
				.dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
				.locations("classpath:db/migration")
				.load()
				.migrate();
	}

	private Connection conn() throws SQLException {
		return DriverManager.getConnection(
				POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword());
	}

	/**
	 * 테스트용 회원 1명 INSERT.
	 * supabase_uid 는 NOT NULL 이므로 호출자가 명시한다. email 은 NULL 가능(소셜 미제공 대응).
	 */
	private void insertUser(Connection c, String supabaseUid, String nickname, String email)
			throws SQLException {
		String emailLiteral = (email == null) ? "NULL" : "'" + email + "'";
		try (Statement st = c.createStatement()) {
			st.executeUpdate(
					"INSERT INTO users (supabase_uid, nickname, email) VALUES ("
							+ "'" + supabaseUid + "', '" + nickname + "', " + emailLiteral + ")");
		}
	}

	// (a) 마이그레이션 적용 + users 테이블 + uq_users_email_active 부분 유니크 인덱스 존재 확인
	@Test
	void migration_appliesAndCreatesUsersWithEmailPartialIndex() throws SQLException {
		try (Connection c = conn()) {
			// users 테이블 존재
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT to_regclass('public.users') IS NOT NULL")) {
				rs.next();
				assertThat(rs.getBoolean(1)).as("users 테이블 존재").isTrue();
			}
			// 이메일 부분 유니크 인덱스 정의 확인
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_users_email_active'")) {
				assertThat(rs.next()).as("uq_users_email_active 인덱스 존재").isTrue();
				assertThat(rs.getString(1))
						.contains("UNIQUE")
						.contains("lower(email)")
						.contains("deleted_at IS NULL");
			}
		}
	}

	// (b) uq_users_supabase_uid: 같은 supabase_uid 중복 INSERT → 유니크 위반(SQLState 23505)
	@Test
	void uniqueConstraint_rejectsDuplicateSupabaseUid() throws SQLException {
		try (Connection c = conn()) {
			String uid = "11111111-1111-1111-1111-111111111111";
			insertUser(c, uid, "first", "first@example.com");

			assertThatThrownBy(() -> insertUser(c, uid, "second", "second@example.com"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23505"));
		}
	}

	// (c) uq_users_email_active: 같은 lower(email) 활성 중복은 거부, 대소문자 무시
	@Test
	void emailPartialIndex_rejectsDuplicateActiveEmail_caseInsensitive() throws SQLException {
		try (Connection c = conn()) {
			insertUser(c, "22222222-2222-2222-2222-222222222222", "u1", "dup@example.com");

			// 대소문자만 다른 동일 이메일(활성) → lower(email) 충돌
			assertThatThrownBy(() -> insertUser(
					c, "33333333-3333-3333-3333-333333333333", "u2", "DUP@EXAMPLE.COM"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23505"));
		}
	}

	// (c) email NULL 은 부분 인덱스 대상이 아니므로 다중 행 허용
	@Test
	void emailPartialIndex_allowsMultipleNullEmails() throws SQLException {
		try (Connection c = conn()) {
			insertUser(c, "44444444-4444-4444-4444-444444444444", "null1", null);
			insertUser(c, "55555555-5555-5555-5555-555555555555", "null2", null);

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT count(*) FROM users WHERE email IS NULL")) {
				rs.next();
				assertThat(rs.getInt(1)).as("email NULL 다중 행 허용").isGreaterThanOrEqualTo(2);
			}
		}
	}

	// (c) 소프트 삭제(deleted_at 설정) 후 같은 이메일 재INSERT 허용 — 부분 인덱스에서 제외됨
	@Test
	void emailPartialIndex_allowsReinsertAfterSoftDelete() throws SQLException {
		try (Connection c = conn()) {
			String email = "recycle@example.com";
			insertUser(c, "66666666-6666-6666-6666-666666666666", "old", email);

			// 기존 회원 소프트 삭제
			try (Statement st = c.createStatement()) {
				st.executeUpdate("UPDATE users SET deleted_at = now() WHERE email = '" + email + "'");
			}

			// 삭제분은 부분 인덱스에서 제외되므로 같은 이메일 재가입 가능해야 한다
			insertUser(c, "77777777-7777-7777-7777-777777777777", "new", email);

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT count(*) FROM users WHERE email = '" + email + "'")) {
				rs.next();
				assertThat(rs.getInt(1)).as("전체 2행(삭제 1 + 활성 1)").isEqualTo(2);
			}
		}
	}
}
