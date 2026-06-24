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
 * Flyway V1 마이그레이션과 핵심 스키마 제약을 Testcontainers PostgreSQL로 검증한다.
 *  (a) 마이그레이션 무오류 적용 + uq_diary_user_day 부분 유니크 인덱스 생성
 *  (b) 같은 (user, written_date) 중복 INSERT → 유니크 제약 위반
 *  (c) 소프트 삭제 후 같은 날짜 재INSERT 허용(부분 인덱스 동작)
 *  (d) ON CONFLICT ... WHERE deleted_at IS NULL DO UPDATE upsert 라운드트립
 */
@Testcontainers
class FlywayMigrationTest {

	@Container
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine");

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

	/** 테스트용 사용자 1명 생성 후 생성된 id 반환 */
	private long insertUser(Connection c, String nickname) throws SQLException {
		try (Statement st = c.createStatement();
				ResultSet rs = st.executeQuery(
						"INSERT INTO users (nickname) VALUES ('" + nickname + "') RETURNING id")) {
			rs.next();
			return rs.getLong(1);
		}
	}

	private void insertDiary(Connection c, long userId, String content, String date) throws SQLException {
		try (Statement st = c.createStatement()) {
			st.executeUpdate(
					"INSERT INTO diaries (user_id, content, written_date) VALUES ("
							+ userId + ", '" + content + "', DATE '" + date + "')");
		}
	}

	// (a) 마이그레이션 적용 + 부분 유니크 인덱스 존재 확인
	@Test
	void migration_appliesAndCreatesPartialUniqueIndex() throws SQLException {
		try (Connection c = conn();
				Statement st = c.createStatement();
				ResultSet rs = st.executeQuery(
						"SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_diary_user_day'")) {
			assertThat(rs.next()).as("uq_diary_user_day 인덱스 존재").isTrue();
			assertThat(rs.getString(1)).contains("UNIQUE").contains("deleted_at IS NULL");
		}
	}

	// (b) 같은 (user, written_date) 중복 INSERT → 유니크 위반(SQLState 23505)
	@Test
	void uniqueIndex_rejectsDuplicateUserDay() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c, "dup_user");
			insertDiary(c, userId, "first", "2026-06-01");

			assertThatThrownBy(() -> insertDiary(c, userId, "second", "2026-06-01"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23505"));
		}
	}

	// (c) 소프트 삭제 후 같은 날짜 재INSERT 허용
	@Test
	void softDelete_allowsReinsertSameDay() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c, "soft_user");
			insertDiary(c, userId, "original", "2026-06-02");

			try (Statement st = c.createStatement()) {
				st.executeUpdate("UPDATE diaries SET deleted_at = now() WHERE user_id = " + userId
						+ " AND written_date = DATE '2026-06-02'");
			}

			// 소프트 삭제분은 부분 인덱스에서 제외되므로 재작성 가능해야 한다
			insertDiary(c, userId, "rewritten", "2026-06-02");

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT count(*) FROM diaries WHERE user_id = " + userId
									+ " AND written_date = DATE '2026-06-02'")) {
				rs.next();
				assertThat(rs.getInt(1)).as("전체 2행(삭제 1 + 활성 1)").isEqualTo(2);
			}
		}
	}

	// (d) ON CONFLICT upsert: 같은 날짜 재저장은 UPDATE(같은 id) + 내용 갱신
	@Test
	void upsert_onConflictUpdatesSameRow() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c, "upsert_user");
			String upsert = "INSERT INTO diaries (user_id, content, written_date) VALUES ("
					+ userId + ", '%s', DATE '2026-06-03') "
					+ "ON CONFLICT (user_id, written_date) WHERE deleted_at IS NULL "
					+ "DO UPDATE SET content = EXCLUDED.content, updated_at = now() RETURNING id";

			long firstId;
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(String.format(upsert, "v1"))) {
				rs.next();
				firstId = rs.getLong(1);
			}

			long secondId;
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(String.format(upsert, "v2"))) {
				rs.next();
				secondId = rs.getLong(1);
			}

			assertThat(secondId).as("같은 행 UPDATE(동일 id)").isEqualTo(firstId);

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT content FROM diaries WHERE id = " + firstId)) {
				rs.next();
				assertThat(rs.getString(1)).as("내용 갱신됨").isEqualTo("v2");
			}
		}
	}
}
