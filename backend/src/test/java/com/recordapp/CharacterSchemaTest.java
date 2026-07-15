package com.recordapp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.concurrent.atomic.AtomicInteger;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 캐릭터 도메인 스키마(V15~V17)를 Testcontainers PostgreSQL 18 로 검증한다.
 * (Task 026 테스트 체크리스트 전 항목)
 *
 * <p>정상 경로
 *  (a) V15~V17 무오류 적용 + 전 테이블·핵심 인덱스 생성
 *  (b) 캐릭터 2종 시드(MONKEY·RED_PANDA) + active=true + rive_artboard 존재
 *  (c) character_lines 맥락(CONFIRM/STREAK_3/…)별 대사 — 캐릭터별·공용 모두
 *  (d) 초기 미션 시드(DIARY_10·STREAK_7·RESOL_1)
 *  (e) group 1개에 캐릭터별 variant 2행 등록 성공
 *
 * <p>제약/예외
 *  (f) uq_variant 중복 INSERT → 23505
 *  (g) uq_character_events_key 중복 INSERT → 23505 (멱등 관문의 물리적 근거)
 *  (h) user_wallets.balance 음수 UPDATE → 23514
 *  (i) chk_missions_reward — coin_reward=0 + item_group_reward NULL → 23514
 *  (j) user_equipment — 단일 슬롯(HAT)에 slot_index=1 → 23514
 *  (k) 미존재 group_code 소유(user_item_groups) → 23503
 *  (l) 미존재 character_code 로 selected_character 설정 → 23503
 *
 * <p>엣지
 *  (m) character_items.character_code NULL 허용(공용) + uq_variant 가 NULL 행에도 동작
 *      (UNIQUE NULLS NOT DISTINCT — 기본 UNIQUE 라면 NULL 중복이 통과해 버린다)
 *  (n) ROOM_PROP 0~5 다중 진열 정상 / 단일 슬롯은 1개만(PK 충돌 23505)
 *  (o) character_events.payload JSONB 왕복
 *  (p) character_items.render_meta JSONB(anchorX/anchorY/scale/z) 왕복
 *
 * <p>운영 DB(PostgreSQL 18, recorme)와 일치시키기 위해 postgres:18-alpine 사용.
 * (uq_variant 의 NULLS NOT DISTINCT 는 PG15+ 문법이라 이미지 버전이 중요하다.)
 */
@Testcontainers
class CharacterSchemaTest {

	@Container
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	/** 테스트 간 users.supabase_uid·email 충돌을 피하기 위한 시퀀스. */
	private static final AtomicInteger SEQ = new AtomicInteger();

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

	// ===================== 테스트 픽스처 =====================

	/**
	 * 테스트용 회원 1명 INSERT 후 users.id 반환(캐릭터 상태 테이블의 FK 부모).
	 * friend_code 는 V11 에서 NOT NULL + UNIQUE 가 됐으므로 함께 채운다(md5 hex 대문자 8자리 —
	 * V11 의 친구코드 알파벳에 포함되고 충돌도 사실상 없다).
	 */
	private long insertUser(Connection c) throws SQLException {
		int n = SEQ.incrementAndGet();
		String uid = String.format("00000000-0000-0000-0000-%012d", n);
		try (Statement st = c.createStatement()) {
			st.executeUpdate(
					"INSERT INTO users (supabase_uid, nickname, email, friend_code) VALUES ('"
							+ uid + "', 'char" + n + "', 'char" + n + "@example.com',"
							+ " upper(substr(md5(random()::text), 1, 8)))");
		}
		try (Statement st = c.createStatement();
				ResultSet rs = st.executeQuery("SELECT id FROM users WHERE supabase_uid = '" + uid + "'")) {
			rs.next();
			return rs.getLong(1);
		}
	}

	/** 테스트 전용 아이템 group 을 만든다(시드를 오염시키지 않기 위해 고유 code 사용). */
	private String insertItemGroup(Connection c, String slot) throws SQLException {
		String code = "T_GRP_" + SEQ.incrementAndGet();
		try (Statement st = c.createStatement()) {
			st.executeUpdate(
					"INSERT INTO item_groups (code, slot, name_ko, thumbnail_url, acquire_type) VALUES ('"
							+ code + "', '" + slot + "', '테스트 아이템', 'assets/items/t.png', 'DEFAULT')");
		}
		return code;
	}

	/** group 소유(user_item_groups) 1행. user_equipment 의 복합 FK 전제. */
	private void own(Connection c, long userId, String groupCode) throws SQLException {
		try (Statement st = c.createStatement()) {
			st.executeUpdate("INSERT INTO user_item_groups (user_id, group_code) VALUES ("
					+ userId + ", '" + groupCode + "')");
		}
	}

	private void equip(Connection c, long userId, String slot, int slotIndex, String groupCode)
			throws SQLException {
		try (Statement st = c.createStatement()) {
			st.executeUpdate("INSERT INTO user_equipment (user_id, slot, slot_index, group_code) VALUES ("
					+ userId + ", '" + slot + "', " + slotIndex + ", '" + groupCode + "')");
		}
	}

	/** character_items variant 1행. characterCode 가 null 이면 공용 variant. */
	private void insertVariant(Connection c, String groupCode, String characterCode, String renderMeta)
			throws SQLException {
		String ch = (characterCode == null) ? "NULL" : "'" + characterCode + "'";
		String meta = (renderMeta == null) ? "NULL" : "'" + renderMeta + "'::jsonb";
		try (Statement st = c.createStatement()) {
			st.executeUpdate(
					"INSERT INTO character_items (group_code, character_code, image_url, rive_slot, render_meta)"
							+ " VALUES ('" + groupCode + "', " + ch + ", 'assets/items/t.png', 'hat', " + meta + ")");
		}
	}

	private void insertEvent(Connection c, long userId, String eventKey, String type, int coinDelta)
			throws SQLException {
		try (Statement st = c.createStatement()) {
			st.executeUpdate(
					"INSERT INTO character_events (user_id, event_key, event_type, coin_delta, balance_after)"
							+ " VALUES (" + userId + ", '" + eventKey + "', '" + type + "', " + coinDelta + ", 0)");
		}
	}

	private void assertSqlState(Throwable e, String expected) {
		assertThat(e).isInstanceOf(SQLException.class);
		assertThat(((SQLException) e).getSQLState()).isEqualTo(expected);
	}

	private int count(Connection c, String sql) throws SQLException {
		try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(sql)) {
			rs.next();
			return rs.getInt(1);
		}
	}

	// ===================== 정상 경로 =====================

	// (a) V15~V17 적용 — 전 테이블 + 핵심 인덱스/제약 생성
	@Test
	void migration_createsAllCharacterTablesAndIndexes() throws SQLException {
		try (Connection c = conn()) {
			String[] tables = {
					"characters", "item_groups", "character_items", "character_lines",     // V15
					"missions", "user_missions",                                           // V16
					"user_character_state", "user_item_groups", "user_equipment",
					"user_progress", "user_wallets", "character_events"                    // V17
			};
			for (String t : tables) {
				try (Statement st = c.createStatement();
						ResultSet rs = st.executeQuery("SELECT to_regclass('public." + t + "') IS NOT NULL")) {
					rs.next();
					assertThat(rs.getBoolean(1)).as(t + " 테이블 존재").isTrue();
				}
			}

			// uq_variant 는 NULLS NOT DISTINCT 유니크(공용 variant 중복 차단의 근거)
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_variant'")) {
				assertThat(rs.next()).as("uq_variant 인덱스 존재").isTrue();
				assertThat(rs.getString(1))
						.contains("UNIQUE")
						.contains("NULLS NOT DISTINCT")
						.contains("group_code")
						.contains("character_code");
			}
			// 멱등 관문 유니크
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_character_events_key'")) {
				assertThat(rs.next()).as("uq_character_events_key 인덱스 존재").isTrue();
				assertThat(rs.getString(1)).contains("UNIQUE").contains("user_id").contains("event_key");
			}
			// 미확인 보상함 부분 인덱스
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT indexdef FROM pg_indexes WHERE indexname = 'idx_character_events_unacked'")) {
				assertThat(rs.next()).as("idx_character_events_unacked 인덱스 존재").isTrue();
				assertThat(rs.getString(1)).contains("acked_at IS NULL");
			}
		}
	}

	// (b) 캐릭터 2종 시드 + active + rive_artboard
	@Test
	void characters_seededWithTwoActiveCharacters() throws SQLException {
		try (Connection c = conn()) {
			assertThat(count(c, "SELECT count(*) FROM characters")).as("캐릭터 2종").isEqualTo(2);
			assertThat(count(c,
					"SELECT count(*) FROM characters WHERE code IN ('MONKEY','RED_PANDA') AND active"))
					.as("MONKEY·RED_PANDA 모두 active").isEqualTo(2);

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT code, name_ko, tagline, rive_artboard, thumbnail_url, sort_order"
									+ " FROM characters ORDER BY sort_order")) {
				assertThat(rs.next()).isTrue();
				assertThat(rs.getString("code")).isEqualTo("MONKEY");
				assertThat(rs.getString("name_ko")).isEqualTo("원숭이");
				assertThat(rs.getString("tagline")).isNotBlank();
				assertThat(rs.getString("rive_artboard")).isEqualTo("monkey");
				assertThat(rs.getString("thumbnail_url")).isEqualTo("assets/characters/monkey.png");

				assertThat(rs.next()).isTrue();
				assertThat(rs.getString("code")).isEqualTo("RED_PANDA");
				assertThat(rs.getString("name_ko")).isEqualTo("레서판다");
				assertThat(rs.getString("tagline")).isNotBlank();
				assertThat(rs.getString("rive_artboard")).isEqualTo("red_panda");
				assertThat(rs.getString("thumbnail_url")).isEqualTo("assets/characters/red_panda.png");
			}
		}
	}

	// (c) character_lines — 맥락 6종 × (캐릭터별 + 공용) 대사 존재
	@Test
	void characterLines_seededPerContext_forEachCharacterAndCommon() throws SQLException {
		try (Connection c = conn()) {
			String[] contexts = {"CONFIRM", "STREAK_3", "STREAK_7", "MISSION", "LEVEL_UP", "IDLE"};
			for (String ctx : contexts) {
				// 캐릭터별 대사(성격 대비의 근거)
				assertThat(count(c, "SELECT count(*) FROM character_lines"
						+ " WHERE context = '" + ctx + "' AND character_code = 'MONKEY'"))
						.as("MONKEY " + ctx + " 대사").isGreaterThanOrEqualTo(2);
				assertThat(count(c, "SELECT count(*) FROM character_lines"
						+ " WHERE context = '" + ctx + "' AND character_code = 'RED_PANDA'"))
						.as("RED_PANDA " + ctx + " 대사").isGreaterThanOrEqualTo(2);
				// 공용 폴백 대사(캐릭터 미선택 상태)
				assertThat(count(c, "SELECT count(*) FROM character_lines"
						+ " WHERE context = '" + ctx + "' AND character_code IS NULL"))
						.as("공용 " + ctx + " 대사").isGreaterThanOrEqualTo(1);
			}
			// 맥락 CHECK: 감정 코드는 context 로 들어올 수 없다
			assertThatThrownBy(() -> {
				try (Statement st = c.createStatement()) {
					st.executeUpdate("INSERT INTO character_lines (character_code, context, line_ko)"
							+ " VALUES ('MONKEY', 'JOY', '감정은 맥락이 아니다')");
				}
			}).satisfies(e -> assertSqlState(e, "23514"));
		}
	}

	// (d) 초기 미션 시드 + 보상 존재
	@Test
	void missions_seededWithInitialSet() throws SQLException {
		try (Connection c = conn()) {
			assertThat(count(c, "SELECT count(*) FROM missions"
					+ " WHERE code IN ('DIARY_10','STREAK_7','RESOL_1')"))
					.as("초기 미션 3종 시드").isEqualTo(3);
			// 모든 미션은 보상(코인 또는 아이템)을 가진다
			assertThat(count(c, "SELECT count(*) FROM missions"
					+ " WHERE coin_reward > 0 OR item_group_reward IS NOT NULL"))
					.isEqualTo(count(c, "SELECT count(*) FROM missions"));

			// rule 타입은 4종(감정·레벨 규칙 없음)
			assertThat(count(c, "SELECT count(*) FROM missions WHERE rule ->> 'type' IN"
					+ " ('DIARY_COUNT','CONSECUTIVE_DAYS','RESOLUTION_SUCCESS','RESOLUTION_STREAK')"))
					.isEqualTo(count(c, "SELECT count(*) FROM missions"));

			// DIARY_10 rule 파싱(MissionEvaluator 가 읽을 형태)
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT rule ->> 'type', (rule ->> 'count')::int, item_group_reward"
									+ " FROM missions WHERE code = 'DIARY_10'")) {
				assertThat(rs.next()).isTrue();
				assertThat(rs.getString(1)).isEqualTo("DIARY_COUNT");
				assertThat(rs.getInt(2)).isEqualTo(10);
				assertThat(rs.getString(3)).isEqualTo("HAT_PARTY");
			}
		}
	}

	// (e) group 1개 + 캐릭터별 variant 2행(★ 2단 구조의 기본형)
	@Test
	void variant_twoRowsPerGroup_forEachCharacter() throws SQLException {
		try (Connection c = conn()) {
			String group = insertItemGroup(c, "OUTFIT");
			insertVariant(c, group, "MONKEY", null);
			insertVariant(c, group, "RED_PANDA", null);

			assertThat(count(c, "SELECT count(*) FROM character_items WHERE group_code = '" + group + "'"))
					.as("group 1개에 캐릭터별 variant 2행").isEqualTo(2);

			// 시드도 동일 구조(OUTFIT_BASIC_TEE = MONKEY·RED_PANDA 2행)
			assertThat(count(c, "SELECT count(*) FROM character_items"
					+ " WHERE group_code = 'OUTFIT_BASIC_TEE' AND character_code IS NOT NULL"))
					.isEqualTo(2);
		}
	}

	// ===================== 제약/예외 =====================

	// (f) uq_variant: 같은 (group, character) 중복 → 23505
	@Test
	void uqVariant_rejectsDuplicateGroupCharacterPair() throws SQLException {
		try (Connection c = conn()) {
			String group = insertItemGroup(c, "HAT");
			insertVariant(c, group, "MONKEY", null);

			assertThatThrownBy(() -> insertVariant(c, group, "MONKEY", null))
					.satisfies(e -> assertSqlState(e, "23505"));
		}
	}

	// (g) uq_character_events_key: 같은 (user, event_key) 중복 → 23505 (★ 멱등 관문)
	@Test
	void uqCharacterEventsKey_rejectsDuplicateEventKey() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			insertEvent(c, userId, "DIARY_CONFIRM:1001", "DIARY_CONFIRM", 10);

			assertThatThrownBy(() -> insertEvent(c, userId, "DIARY_CONFIRM:1001", "DIARY_CONFIRM", 10))
					.satisfies(e -> assertSqlState(e, "23505"));

			// 같은 event_key 라도 사용자가 다르면 허용(멱등 범위는 사용자 단위)
			long other = insertUser(c);
			insertEvent(c, other, "DIARY_CONFIRM:1001", "DIARY_CONFIRM", 10);

			// ON CONFLICT DO NOTHING 이 0행 → no-op 임을 확인(Task 028 게이트의 실제 사용 형태)
			try (Statement st = c.createStatement()) {
				int affected = st.executeUpdate(
						"INSERT INTO character_events (user_id, event_key, event_type, coin_delta)"
								+ " VALUES (" + userId + ", 'DIARY_CONFIRM:1001', 'DIARY_CONFIRM', 10)"
								+ " ON CONFLICT (user_id, event_key) DO NOTHING");
				assertThat(affected).as("이미 처리된 이벤트 → 0행(no-op)").isZero();
			}
		}
	}

	// (h) user_wallets.balance 음수 UPDATE → 23514 (코인 소비 경합의 최종 방어선)
	@Test
	void walletBalance_rejectsNegative() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			try (Statement st = c.createStatement()) {
				st.executeUpdate("INSERT INTO user_wallets (user_id, balance) VALUES (" + userId + ", 50)");
			}

			assertThatThrownBy(() -> {
				try (Statement st = c.createStatement()) {
					st.executeUpdate("UPDATE user_wallets SET balance = balance - 100 WHERE user_id = " + userId);
				}
			}).satisfies(e -> assertSqlState(e, "23514"));

			// 경합 안전 소비 패턴: WHERE balance >= ? → 0행이면 애플리케이션이 409 로 거른다
			try (Statement st = c.createStatement()) {
				int affected = st.executeUpdate(
						"UPDATE user_wallets SET balance = balance - 100"
								+ " WHERE user_id = " + userId + " AND balance >= 100");
				assertThat(affected).as("잔액 부족 → 0행").isZero();
			}
			assertThat(count(c, "SELECT balance FROM user_wallets WHERE user_id = " + userId)).isEqualTo(50);
		}
	}

	// (i) chk_missions_reward: coin_reward=0 + item_group_reward NULL → 23514
	@Test
	void chkMissionsReward_rejectsMissionWithoutReward() throws SQLException {
		try (Connection c = conn()) {
			assertThatThrownBy(() -> {
				try (Statement st = c.createStatement()) {
					st.executeUpdate("INSERT INTO missions (code, title, description, rule, coin_reward)"
							+ " VALUES ('T_NO_REWARD', '보상 없음', '보상 없는 미션',"
							+ " '{\"type\":\"DIARY_COUNT\",\"count\":3}', 0)");
				}
			}).satisfies(e -> assertSqlState(e, "23514"));

			// 아이템 보상만 있어도 통과
			assertThatCode(() -> {
				try (Statement st = c.createStatement()) {
					st.executeUpdate(
							"INSERT INTO missions (code, title, description, rule, coin_reward, item_group_reward)"
									+ " VALUES ('T_ITEM_ONLY', '아이템만', '아이템 보상만',"
									+ " '{\"type\":\"DIARY_COUNT\",\"count\":2}', 0, 'HAT_PARTY')");
				}
			}).doesNotThrowAnyException();
		}
	}

	// (j) user_equipment: 단일 슬롯(HAT)에 slot_index=1 → 23514
	@Test
	void equipmentSlotIndexCheck_rejectsNonZeroIndexOnSingleSlot() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			String hat = insertItemGroup(c, "HAT");
			own(c, userId, hat);

			assertThatThrownBy(() -> equip(c, userId, "HAT", 1, hat))
					.satisfies(e -> assertSqlState(e, "23514"));

			// slot_index=0 이면 정상
			assertThatCode(() -> equip(c, userId, "HAT", 0, hat)).doesNotThrowAnyException();
		}
	}

	// (k) FK: 존재하지 않는 group_code 소유 → 23503
	@Test
	void fkUserItemGroups_rejectsUnknownGroupCode() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			assertThatThrownBy(() -> own(c, userId, "NO_SUCH_GROUP"))
					.satisfies(e -> assertSqlState(e, "23503"));
		}
	}

	// (l) FK: 존재하지 않는 character_code 로 selected_character 설정 → 23503
	@Test
	void fkUserCharacterState_rejectsUnknownCharacterCode() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			assertThatThrownBy(() -> {
				try (Statement st = c.createStatement()) {
					st.executeUpdate("INSERT INTO user_character_state (user_id, selected_character)"
							+ " VALUES (" + userId + ", 'CAT')");
				}
			}).satisfies(e -> assertSqlState(e, "23503"));

			// 시드된 캐릭터는 통과
			try (Statement st = c.createStatement()) {
				st.executeUpdate("INSERT INTO user_character_state (user_id, selected_character)"
						+ " VALUES (" + userId + ", 'MONKEY')");
			}
			assertThat(count(c, "SELECT count(*) FROM user_character_state WHERE user_id = " + userId
					+ " AND selected_character = 'MONKEY'"))
					.isEqualTo(1);
		}
	}

	// (l-2) 미보유 group 착용은 복합 FK 로 차단 → 23503 (서비스 409 ITEM_NOT_OWNED 의 최종 방어선)
	@Test
	void fkUserEquipment_rejectsEquippingUnownedGroup() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			String hat = insertItemGroup(c, "HAT");   // 존재하지만 소유하지 않은 group

			assertThatThrownBy(() -> equip(c, userId, "HAT", 0, hat))
					.satisfies(e -> assertSqlState(e, "23503"));
		}
	}

	// ===================== 엣지 =====================

	// (m) ★ 공용 variant(character_code NULL) 허용 + uq_variant 가 NULL 행에도 동작
	//     기본 UNIQUE 는 NULL 을 서로 다른 값으로 보므로 중복이 통과해 버린다.
	//     NULLS NOT DISTINCT 를 썼기 때문에 두 번째 NULL 행이 23505 로 거부되어야 한다.
	@Test
	void uqVariant_nullCharacterCode_isAllowedOnce_andDuplicateRejected() throws SQLException {
		try (Connection c = conn()) {
			String group = insertItemGroup(c, "ROOM_PROP");

			// 공용 variant 1행은 허용
			insertVariant(c, group, null, null);
			assertThat(count(c, "SELECT count(*) FROM character_items"
					+ " WHERE group_code = '" + group + "' AND character_code IS NULL"))
					.as("공용 variant 1행 허용").isEqualTo(1);

			// ★ 같은 group 의 공용 variant 중복 → NULLS NOT DISTINCT 로 23505
			assertThatThrownBy(() -> insertVariant(c, group, null, null))
					.as("NULL 행 중복도 uq_variant 가 차단")
					.satisfies(e -> assertSqlState(e, "23505"));

			// 공용 행이 있어도 캐릭터 전용 variant 는 별개 키라 추가 가능
			assertThatCode(() -> insertVariant(c, group, "MONKEY", null)).doesNotThrowAnyException();

			// 시드 공용 variant(ROOM_PROP_PLANT·BG_COZY_ROOM)도 각 1행
			assertThat(count(c, "SELECT count(*) FROM character_items"
					+ " WHERE group_code IN ('ROOM_PROP_PLANT','BG_COZY_ROOM') AND character_code IS NULL"))
					.isEqualTo(2);
		}
	}

	// (n) ROOM_PROP 0~5 다중 진열 정상 / 단일 슬롯(HAT)은 1개만
	@Test
	void equipment_roomPropAllowsSixSlots_singleSlotAllowsOne() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);

			// ROOM_PROP 6칸(0~5) — 같은 아이템 중복 진열은 uq_user_equipment_group 이 막으므로 group 6개
			for (int i = 0; i <= 5; i++) {
				String prop = insertItemGroup(c, "ROOM_PROP");
				own(c, userId, prop);
				equip(c, userId, "ROOM_PROP", i, prop);
			}
			assertThat(count(c, "SELECT count(*) FROM user_equipment"
					+ " WHERE user_id = " + userId + " AND slot = 'ROOM_PROP'"))
					.as("ROOM_PROP 0~5 다중 진열").isEqualTo(6);

			// 범위 밖(6번 칸) 거부
			String extra = insertItemGroup(c, "ROOM_PROP");
			own(c, userId, extra);
			assertThatThrownBy(() -> equip(c, userId, "ROOM_PROP", 6, extra))
					.satisfies(e -> assertSqlState(e, "23514"));

			// 단일 슬롯(HAT)은 1개만 — 두 번째 HAT 은 PK(user_id, slot, slot_index=0) 충돌
			String hat1 = insertItemGroup(c, "HAT");
			String hat2 = insertItemGroup(c, "HAT");
			own(c, userId, hat1);
			own(c, userId, hat2);
			equip(c, userId, "HAT", 0, hat1);

			assertThatThrownBy(() -> equip(c, userId, "HAT", 0, hat2))
					.as("단일 슬롯은 1개만")
					.satisfies(e -> assertSqlState(e, "23505"));

			// 교체는 UPDATE/DELETE→INSERT 로(배치 교체 = Task 027)
			try (Statement st = c.createStatement()) {
				st.executeUpdate("UPDATE user_equipment SET group_code = '" + hat2 + "'"
						+ " WHERE user_id = " + userId + " AND slot = 'HAT' AND slot_index = 0");
			}
			assertThat(count(c, "SELECT count(*) FROM user_equipment"
					+ " WHERE user_id = " + userId + " AND slot = 'HAT'"))
					.isEqualTo(1);
		}
	}

	// (o) character_events.payload JSONB 왕복(리액션 페이로드) + acked_at 알림함 동작
	@Test
	void characterEvents_payloadJsonbRoundTrip_andUnackedCount() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			String payload = "{\"line\":\"오늘도 한 줄 남겼네.\",\"character\":\"MONKEY\","
					+ "\"coin\":10,\"missions\":[\"DIARY_10\"]}";
			try (Statement st = c.createStatement()) {
				st.executeUpdate(
						"INSERT INTO character_events (user_id, event_key, event_type, coin_delta, balance_after, payload)"
								+ " VALUES (" + userId + ", 'DIARY_CONFIRM:2002', 'DIARY_CONFIRM', 10, 10,"
								+ " '" + payload + "'::jsonb)");
			}

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT payload ->> 'line', payload ->> 'character', (payload ->> 'coin')::int,"
									+ " payload -> 'missions' ->> 0"
									+ " FROM character_events WHERE user_id = " + userId
									+ " AND event_key = 'DIARY_CONFIRM:2002'")) {
				assertThat(rs.next()).isTrue();
				assertThat(rs.getString(1)).isEqualTo("오늘도 한 줄 남겼네.");
				assertThat(rs.getString(2)).isEqualTo("MONKEY");
				assertThat(rs.getInt(3)).isEqualTo(10);
				assertThat(rs.getString(4)).isEqualTo("DIARY_10");
			}

			// 미확인 보상함(acked_at IS NULL) → ack 후 0
			assertThat(count(c, "SELECT count(*) FROM character_events"
					+ " WHERE user_id = " + userId + " AND acked_at IS NULL")).isEqualTo(1);
			try (Statement st = c.createStatement()) {
				st.executeUpdate("UPDATE character_events SET acked_at = now()"
						+ " WHERE user_id = " + userId + " AND acked_at IS NULL");
			}
			assertThat(count(c, "SELECT count(*) FROM character_events"
					+ " WHERE user_id = " + userId + " AND acked_at IS NULL")).isZero();
		}
	}

	// (p) character_items.render_meta JSONB(anchorX/anchorY/scale/z) 왕복
	@Test
	void characterItems_renderMetaJsonbRoundTrip() throws SQLException {
		try (Connection c = conn()) {
			String group = insertItemGroup(c, "HAT");
			insertVariant(c, group, "RED_PANDA",
					"{\"anchorX\":0.5,\"anchorY\":0.16,\"scale\":0.48,\"z\":40}");

			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT (render_meta ->> 'anchorX')::numeric, (render_meta ->> 'anchorY')::numeric,"
									+ " (render_meta ->> 'scale')::numeric, (render_meta ->> 'z')::int, rive_slot"
									+ " FROM character_items WHERE group_code = '" + group + "'")) {
				assertThat(rs.next()).isTrue();
				assertThat(rs.getDouble(1)).isEqualTo(0.5);
				assertThat(rs.getDouble(2)).isEqualTo(0.16);
				assertThat(rs.getDouble(3)).isEqualTo(0.48);
				assertThat(rs.getInt(4)).isEqualTo(40);
				assertThat(rs.getString(5)).isEqualTo("hat");
			}

			// 시드 variant 도 render_meta 4키를 갖는다(플레이스홀더 렌더러 전제 — Task 029).
			// jsonb 존재 연산자(?&)는 JDBC 의 파라미터 플레이스홀더와 충돌하므로 ->> IS NOT NULL 로 검사한다.
			assertThat(count(c, "SELECT count(*) FROM character_items"
					+ " WHERE render_meta ->> 'anchorX' IS NOT NULL"
					+ " AND render_meta ->> 'anchorY' IS NOT NULL"
					+ " AND render_meta ->> 'scale' IS NOT NULL"
					+ " AND render_meta ->> 'z' IS NOT NULL"))
					.as("시드 variant 8행 + 방금 넣은 1행")
					.isGreaterThanOrEqualTo(9);
		}
	}

	// (q) user_progress — 미션 판정 O(1) 캐시의 기본값·음수 방어
	@Test
	void userProgress_defaultsAndNonNegativeCheck() throws SQLException {
		try (Connection c = conn()) {
			long userId = insertUser(c);
			try (Statement st = c.createStatement()) {
				st.executeUpdate("INSERT INTO user_progress (user_id) VALUES (" + userId + ")");
			}
			try (Statement st = c.createStatement();
					ResultSet rs = st.executeQuery(
							"SELECT confirmed_diary_count, consecutive_days, last_confirmed_date,"
									+ " resolution_success_count, max_streak_seq"
									+ " FROM user_progress WHERE user_id = " + userId)) {
				assertThat(rs.next()).isTrue();
				assertThat(rs.getInt(1)).isZero();
				assertThat(rs.getInt(2)).isZero();
				assertThat(rs.getDate(3)).isNull();
				assertThat(rs.getInt(4)).isZero();
				assertThat(rs.getInt(5)).isZero();
			}

			assertThatThrownBy(() -> {
				try (Statement st = c.createStatement()) {
					st.executeUpdate("UPDATE user_progress SET confirmed_diary_count = -1"
							+ " WHERE user_id = " + userId);
				}
			}).satisfies(e -> assertSqlState(e, "23514"));
		}
	}
}
