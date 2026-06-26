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
 * Flyway V1(users)·V2(diaries) 마이그레이션과 스키마 제약을 Testcontainers PostgreSQL로 검증한다.
 *  (a) 마이그레이션 무오류 적용 + users 테이블 생성 + uq_users_email_active 부분 유니크 인덱스
 *  (b) uq_users_supabase_uid: 같은 supabase_uid 중복 INSERT → 유니크 제약 위반
 *  (c) uq_users_email_active: 같은 lower(email) 활성 중복 거부 /
 *      email NULL 다중 행 허용 / 소프트 삭제 후 같은 email 재INSERT 허용
 *
 * diaries(V2) 검증:
 *  (d) diaries 테이블 + uq_diary_user_day 부분 유니크 인덱스(UNIQUE·deleted_at IS NULL) 존재
 *  (e) uq_diary_user_day: 같은 user_id+written_date 활성 중복 거부(23505) /
 *      소프트 삭제 후 같은 날짜 재INSERT 허용
 *  (f) chk_diaries_content_len: 501자·빈 문자열 content INSERT 거부(23514)
 *
 * diary_images 제거(V5) 검증:
 *  (g) V5 가 diary_images 테이블을 제거(인라인 이미지는 diaries.content Delta 가 단일 진실원)
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

	/**
	 * 테스트용 회원 1명 INSERT 후 IDENTITY 로 발급된 users.id 를 조회해 반환한다.
	 * diaries 는 user_id FK(NOT NULL)가 필요하므로 부모 행 생성 + id 확보용.
	 * 호출자가 매번 고유한 supabase_uid·email 을 넘겨 충돌을 피한다.
	 */
	private long insertUserAndGetId(Connection c, String supabaseUid, String nickname, String email)
			throws SQLException {
		insertUser(c, supabaseUid, nickname, email);
		try (Statement st = c.createStatement();
				ResultSet rs = st.executeQuery(
						"SELECT id FROM users WHERE supabase_uid = '" + supabaseUid + "'")) {
			rs.next();
			return rs.getLong(1);
		}
	}

	/**
	 * 테스트용 일기 1건 INSERT. content·written_date 만 지정하고 나머지는 DDL 기본값에 맡긴다.
	 * written_date 는 'YYYY-MM-DD' 문자열로 전달한다.
	 */
	private void insertDiary(Connection c, long userId, String content, String writtenDate)
			throws SQLException {
		try (Statement st = c.createStatement()) {
			st.executeUpdate(
					"INSERT INTO diaries (user_id, content, written_date) VALUES ("
							+ userId + ", '" + content + "', DATE '" + writtenDate + "')");
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

	// ===================== diaries(V2) =====================

	// (d) diaries 테이블 + uq_diary_user_day 부분 유니크 인덱스(UNIQUE·deleted_at IS NULL) 존재 확인
	@Test
	void diaries_table_and_partialUniqueIndex_exist() throws SQLException {
		try (Connection c = conn()) {
			// diaries 테이블 존재
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT to_regclass('public.diaries') IS NOT NULL")) {
				rs.next();
				assertThat(rs.getBoolean(1)).as("diaries 테이블 존재").isTrue();
			}
			// 하루 1기록 부분 유니크 인덱스 정의 확인
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_diary_user_day'")) {
				assertThat(rs.next()).as("uq_diary_user_day 인덱스 존재").isTrue();
				assertThat(rs.getString(1))
						.contains("UNIQUE")
						.contains("deleted_at IS NULL");
			}
		}
	}

	// (e) uq_diary_user_day: 같은 user_id+written_date 활성 2건 → 유니크 위반(SQLState 23505)
	@Test
	void uqDiaryUserDay_rejectsDuplicateActiveDay() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "88888888-8888-8888-8888-888888888888", "diary_dup", "diarydup@example.com");
			insertDiary(c, userId, "오늘의 첫 기록", "2026-06-26");

			// 같은 사용자·같은 날짜 활성 일기 재INSERT → 충돌
			assertThatThrownBy(() -> insertDiary(c, userId, "같은 날 두 번째 기록", "2026-06-26"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23505"));
		}
	}

	// (e) 소프트 삭제 후 같은 날짜 재INSERT 허용 — 부분 인덱스에서 제외됨
	@Test
	void uqDiaryUserDay_allowsReinsertAfterSoftDelete() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "99999999-9999-9999-9999-999999999999", "diary_recycle", "diaryrecycle@example.com");
			String day = "2026-06-25";
			insertDiary(c, userId, "삭제될 기록", day);

			// 기존 일기 소프트 삭제
			try (Statement st = c.createStatement()) {
				st.executeUpdate(
						"UPDATE diaries SET deleted_at = now() WHERE user_id = " + userId
								+ " AND written_date = DATE '" + day + "'");
			}

			// 삭제분은 부분 인덱스에서 제외되므로 같은 날짜 재작성 가능해야 한다
			insertDiary(c, userId, "다시 쓴 기록", day);

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT count(*) FROM diaries WHERE user_id = " + userId
									+ " AND written_date = DATE '" + day + "'")) {
				rs.next();
				assertThat(rs.getInt(1)).as("전체 2행(삭제 1 + 활성 1)").isEqualTo(2);
			}
		}
	}

	// (f) chk_diaries_content_len: 501자·빈 문자열 content → 체크 제약 위반(SQLState 23514)
	@Test
	void contentCheck_rejectsTooLongAndEmpty() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "diary_len", "diarylen@example.com");

			// 501자(최대 500 초과) → check_violation
			String tooLong = "x".repeat(501);
			assertThatThrownBy(() -> insertDiary(c, userId, tooLong, "2026-06-24"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23514"));

			// 빈 문자열(최소 1 미만) → check_violation
			assertThatThrownBy(() -> insertDiary(c, userId, "", "2026-06-23"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23514"));
		}
	}

	// ===================== diary_images 제거(V5) =====================

	// (g) V5 가 diary_images 테이블을 제거한다(인라인 이미지는 diaries.content Delta 가 단일 진실원)
	@Test
	void diaryImages_tableDroppedByV5() throws SQLException {
		try (Connection c = conn()) {
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT to_regclass('public.diary_images') IS NULL")) {
				rs.next();
				assertThat(rs.getBoolean(1)).as("V5 가 diary_images 테이블 제거").isTrue();
			}
		}
	}
}
