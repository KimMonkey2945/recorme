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
 * 감정 분석(V7) 검증:
 *  (h) emotion_types 시드 6행 존재(각 code 포함)
 *  (i) diaries 에 분석 컬럼 9개 추가(primary_emotion·emotion_scores·analyzed_at 등)
 *  (j) fk_diaries_emotion: 미존재 감정 코드로 primary_emotion UPDATE → 외래키 위반(23503)
 *  (k) chk_diaries_*_color: 잘못된 색 형식 → 체크 위반(23514) / #RRGGBB·#RRGGBBAA 통과
 *  (l) chk_diaries_done_has_emotion: primary_emotion NULL 인데 DONE → 위반(23514) /
 *      주감정 채운 뒤 DONE 통과
 *
 * draft 라이프사이클(V8) 검증:
 *  (m) analysis_status 컬럼 기본값이 'DRAFT'(information_schema.columns.column_default)
 *  (n) chk_diaries_analysis_status: 허용 외 값('XXX') INSERT/UPDATE → 체크 위반(23514) /
 *      DRAFT·PENDING·DONE·FAILED 는 통과
 *  (o) DRAFT + primary_emotion NULL 행 정상 INSERT(V7 chk_diaries_done_has_emotion 과 무충돌)
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
	 * 테스트용 기록 1건 INSERT. content·written_date 만 지정하고 나머지는 DDL 기본값에 맡긴다.
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

			// 같은 사용자·같은 날짜 활성 기록 재INSERT → 충돌
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

			// 기존 기록 소프트 삭제
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

	// ===================== 감정 분석(V7) =====================

	/**
	 * diaries 단일 컬럼 값을 user_id 기준으로 UPDATE 한다(테스트마다 user 1명·기록 1건 전제).
	 * 잘못된 값으로 호출해 CHECK/FK 위반(SQLState)을 검증하는 데 쓴다.
	 */
	private void updateDiaryColumn(Connection c, long userId, String setClause) throws SQLException {
		try (Statement st = c.createStatement()) {
			st.executeUpdate("UPDATE diaries SET " + setClause + " WHERE user_id = " + userId);
		}
	}

	// (h) emotion_types 시드 6행이 모두 존재하는지 확인(대표 code 일부 포함)
	@Test
	void emotionTypes_seededWithSixRows() throws SQLException {
		try (Connection c = conn()) {
			// 전체 6행
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery("SELECT count(*) FROM emotion_types")) {
				rs.next();
				assertThat(rs.getInt(1)).as("emotion_types 시드 6행").isEqualTo(6);
			}
			// 핵심 code 존재(JOY·NEUTRAL) + 라벨 매핑 확인
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT label_ko FROM emotion_types WHERE code = 'JOY'")) {
				assertThat(rs.next()).as("JOY 코드 존재").isTrue();
				assertThat(rs.getString(1)).isEqualTo("기쁨");
			}
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT count(*) FROM emotion_types "
									+ "WHERE code IN ('JOY','SADNESS','ANGER','CALM','ANXIETY','NEUTRAL')")) {
				rs.next();
				assertThat(rs.getInt(1)).as("6종 코드 모두 시드").isEqualTo(6);
			}
		}
	}

	// (i) diaries 에 V7 분석 컬럼 9개가 모두 추가되었는지 information_schema.columns 로 확인
	@Test
	void diaries_hasEmotionAnalysisColumns() throws SQLException {
		try (Connection c = conn()) {
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT count(*) FROM information_schema.columns "
									+ "WHERE table_name = 'diaries' AND column_name IN ("
									+ "'primary_emotion','background_color','text_color','accent_color',"
									+ "'ai_comment','ai_title','mood_emoji','emotion_scores','analyzed_at')")) {
				rs.next();
				assertThat(rs.getInt(1)).as("diaries 분석 컬럼 9개 존재").isEqualTo(9);
			}
			// emotion_scores 는 JSONB 타입이어야 한다
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT data_type FROM information_schema.columns "
									+ "WHERE table_name = 'diaries' AND column_name = 'emotion_scores'")) {
				assertThat(rs.next()).as("emotion_scores 컬럼 존재").isTrue();
				assertThat(rs.getString(1)).isEqualTo("jsonb");
			}
		}
	}

	// (j) fk_diaries_emotion: 존재하지 않는 감정 코드로 primary_emotion UPDATE → 외래키 위반(23503)
	@Test
	void fkDiariesEmotion_rejectsUnknownEmotionCode() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "emo_fk", "emofk@example.com");
			insertDiary(c, userId, "감정 분석 대상", "2026-06-22");

			// emotion_types 에 없는 코드 → 외래키 위반
			assertThatThrownBy(() -> updateDiaryColumn(c, userId, "primary_emotion = 'XXX'"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23503"));

			// 시드된 코드(JOY)는 통과해야 한다
			updateDiaryColumn(c, userId, "primary_emotion = 'JOY'");
		}
	}

	// (k) chk_diaries_*_color: 잘못된 색 형식 → 체크 위반(23514), #RRGGBB·#RRGGBBAA 는 통과
	@Test
	void colorCheck_rejectsInvalidHexAndAllowsValid() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "cccccccc-cccc-cccc-cccc-cccccccccccc", "emo_color", "emocolor@example.com");
			insertDiary(c, userId, "색 검증 대상", "2026-06-21");

			// 형식 위반(# 누락·길이 불일치) → check_violation
			assertThatThrownBy(() -> updateDiaryColumn(c, userId, "background_color = 'not-a-hex'"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23514"));

			// #RRGGBB(6자리) 통과
			updateDiaryColumn(c, userId, "background_color = '#A1B2C3'");
			// #RRGGBBAA(8자리 알파) 통과 + 다른 색 컬럼도 동일 규칙
			updateDiaryColumn(c, userId, "text_color = '#A1B2C3FF', accent_color = '#0a0B0c'");
		}
	}

	// (l) chk_diaries_done_has_emotion: primary_emotion NULL 인데 DONE → 위반(23514), 채우면 통과
	@Test
	void doneStatusCheck_requiresPrimaryEmotion() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "dddddddd-dddd-dddd-dddd-dddddddddddd", "emo_done", "emodone@example.com");
			insertDiary(c, userId, "상태 정합 검증 대상", "2026-06-20");

			// primary_emotion NULL 상태에서 DONE 전환 → 체크 위반
			assertThatThrownBy(() -> updateDiaryColumn(c, userId, "analysis_status = 'DONE'"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23514"));

			// 주감정을 채운 뒤 DONE 으로 전환하면 통과
			updateDiaryColumn(c, userId, "primary_emotion = 'CALM', analysis_status = 'DONE'");

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT analysis_status FROM diaries WHERE user_id = " + userId)) {
				rs.next();
				assertThat(rs.getString(1)).as("주감정 채운 뒤 DONE 적용").isEqualTo("DONE");
			}
		}
	}

	// ===================== draft 라이프사이클(V8) =====================

	// (m) V8: analysis_status 컬럼 기본값이 'DRAFT' 로 전환됐는지 확인(등록 시 미확정 출발)
	@Test
	void analysisStatus_defaultIsDraft() throws SQLException {
		try (Connection c = conn()) {
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT column_default FROM information_schema.columns "
									+ "WHERE table_name = 'diaries' AND column_name = 'analysis_status'")) {
				assertThat(rs.next()).as("analysis_status 컬럼 존재").isTrue();
				// 예: 'DRAFT'::character varying — 리터럴에 DRAFT 포함 확인
				assertThat(rs.getString(1)).as("기본값 DRAFT").contains("DRAFT");
			}
		}
	}

	// (n) chk_diaries_analysis_status: 허용 외 값은 거부(23514), 4종 상태값은 통과
	@Test
	void analysisStatusCheck_rejectsUnknownAndAllowsAllowedSet() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", "draft_chk", "draftchk@example.com");
			insertDiary(c, userId, "상태값 검증 대상", "2026-06-19");

			// 허용 집합 밖('XXX') → 체크 위반
			assertThatThrownBy(() -> updateDiaryColumn(c, userId, "analysis_status = 'XXX'"))
					.isInstanceOf(SQLException.class)
					.satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("23514"));

			// DRAFT/PENDING/FAILED 는 통과(주감정 NULL 허용 상태들). DONE 은 별도 CHECK 가 주감정을 요구하므로 (l)에서 검증.
			updateDiaryColumn(c, userId, "analysis_status = 'DRAFT'");
			updateDiaryColumn(c, userId, "analysis_status = 'PENDING'");
			updateDiaryColumn(c, userId, "analysis_status = 'FAILED'");

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT analysis_status FROM diaries WHERE user_id = " + userId)) {
				rs.next();
				assertThat(rs.getString(1)).isEqualTo("FAILED");
			}
		}
	}

	// (o) DRAFT + primary_emotion NULL 행 정상 INSERT — V7 chk_diaries_done_has_emotion 과 무충돌
	@Test
	void draftRow_withNullEmotion_insertsCleanly() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUserAndGetId(
					c, "ffffffff-ffff-ffff-ffff-ffffffffffff", "draft_null", "draftnull@example.com");
			// analysis_status 미지정 → 기본값 DRAFT 로 INSERT(primary_emotion 도 NULL). 어떤 CHECK 도 위반하지 않는다.
			insertDiary(c, userId, "미확정 초안", "2026-06-18");

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT analysis_status, primary_emotion FROM diaries WHERE user_id = " + userId)) {
				assertThat(rs.next()).as("DRAFT 행 INSERT 성공").isTrue();
				assertThat(rs.getString(1)).as("기본값 DRAFT 적용").isEqualTo("DRAFT");
				assertThat(rs.getString(2)).as("DRAFT 는 주감정 NULL 허용").isNull();
			}
		}
	}
}
