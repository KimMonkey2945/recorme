package com.recordapp.domain.character;

import static org.assertj.core.api.Assertions.assertThat;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.character.dto.EmotionStat;
import com.recordapp.domain.character.dto.RetrospectResponse;
import com.recordapp.domain.character.dto.UnlockedItem;
import com.recordapp.domain.character.service.CharacterService;
import com.recordapp.domain.character.service.RetrospectService;
import com.recordapp.global.security.SupabaseClaims;
import java.time.YearMonth;
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
 * 월간 회고(Task 032) 통합 테스트(Testcontainers PostgreSQL 18).
 *
 * <p>서비스를 직접 호출해 <b>확정 수·최장 연속일·감정 분포(프리셋+커스텀 혼재)·획득 코인·완주 수·획득 아이템</b>
 * 집계가 실제 DB 에서 정확한지, 빈 달·타 사용자 격리(IDOR)가 성립하는지 검증한다.
 *
 * <p>⚠️ {@code @Transactional} 을 두지 않는다(CharacterRewardServiceTest 동일) — JIT ensureState 와
 * 직접 INSERT 가 실제 커밋돼야 집계 대상이 된다. 사용자는 JIT 프로비저닝, 데이터는 JdbcTemplate 직접 INSERT.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class RetrospectServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	RetrospectService retrospectService;

	@Autowired
	CharacterService characterService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	private static final YearMonth JULY = YearMonth.of(2026, 7);

	// ===== 헬퍼 =====

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	private long newUser() {
		String sub = UUID.randomUUID().toString();
		return provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", "tester"), Map.of("sub", sub)))
				.userId();
	}

	/** 확정/미확정 기록 INSERT. primaryEmotion·emotionLabel 은 상호 배타(둘 다 null 이면 감정 미입력). */
	private void newDiary(long userId, String date, String status, String primaryEmotion, String emotionLabel) {
		jdbc().update(
				"INSERT INTO diaries (user_id, content, content_text, written_date, analysis_status, "
						+ "primary_emotion, emotion_label) "
						+ "VALUES (?, '{\"ops\":[{\"insert\":\"오늘\\n\"}]}', '오늘', ?::date, ?, ?, ?)",
				userId, date, status, primaryEmotion, emotionLabel);
	}

	/**
	 * character_events 원장 직접 INSERT(created_at 을 KST 기준으로 명시해 월 범위를 정확히 흉내낸다).
	 * balance_after 는 NULL 로 둔다 — 집계는 coin_delta 만 쓰고, 음수 balance_after 는 CHECK 위반이라.
	 */
	private void newEvent(long userId, String eventKey, String eventType, int coinDelta, String createdAtKst) {
		jdbc().update(
				"INSERT INTO character_events (user_id, event_key, event_type, coin_delta, created_at) "
						+ "VALUES (?, ?, ?, ?, ?::timestamptz)",
				userId, eventKey, eventType, coinDelta, createdAtKst);
	}

	/** 아이템 group 소유 부여(acquired_at 명시). group_code 는 item_groups FK(V21 카탈로그). */
	private void acquireItem(long userId, String groupCode, String acquiredAtKst) {
		jdbc().update(
				"INSERT INTO user_item_groups (user_id, group_code, acquired_at) VALUES (?, ?, ?::timestamptz)",
				userId, groupCode, acquiredAtKst);
	}

	private void selectCharacter(long userId, String code) {
		jdbc().update("UPDATE user_character_state SET selected_character = ? WHERE user_id = ?", code, userId);
	}

	// ===== ① 정상: 종합 집계 정확 =====

	@Test
	void 월간_회고_종합_집계가_정확하다() {
		long userId = newUser();
		characterService.ensureState(userId); // 상태 행 보장(이후 selected_character 갱신)
		selectCharacter(userId, "MONKEY"); // 획득 아이템 이미지가 MONKEY variant 로 해석되도록

		// 확정 기록: 7/1·7/2·7/3(연속 3) → 7/4 는 DRAFT(제외) → 7/5·7/6(연속 2) → 7/10(단독)
		newDiary(userId, "2026-07-01", "DONE", "JOY", null);
		newDiary(userId, "2026-07-02", "DONE", "JOY", null);
		newDiary(userId, "2026-07-03", "DONE", "CALM", null);
		newDiary(userId, "2026-07-04", "DRAFT", "ANGER", null); // 미확정 — 집계·연속에서 제외
		newDiary(userId, "2026-07-05", "DONE", null, "설레는"); // 직접 입력 감정
		newDiary(userId, "2026-07-06", "DONE", "JOY", null);
		newDiary(userId, "2026-07-10", "DONE", null, null); // 감정 미입력 — 분포에서 제외
		newDiary(userId, "2026-06-30", "DONE", "JOY", null); // 다른 달 — 전부 제외

		// 코인 원장: 7월 +10 +200 +50(완주) / 구매 -50(제외) / 6월 +10(제외)
		newEvent(userId, "E_DIARY", "DIARY_CONFIRM", 10, "2026-07-01 09:00:00+09");
		newEvent(userId, "E_STREAK", "STREAK", 200, "2026-07-07 09:00:00+09");
		newEvent(userId, "E_RESO", "RESOLUTION_SUCCESS", 50, "2026-07-08 09:00:00+09");
		newEvent(userId, "E_BUY", "PURCHASE", -50, "2026-07-06 09:00:00+09"); // 소비 — coinEarned 제외
		newEvent(userId, "E_JUN", "ATTENDANCE", 10, "2026-06-20 09:00:00+09"); // 다른 달 — 제외

		// 획득 아이템: 7월 HAT_CAP_BLACK / 6월 GLASSES_ROUND(제외)
		acquireItem(userId, "HAT_CAP_BLACK", "2026-07-06 12:00:00+09");
		acquireItem(userId, "GLASSES_ROUND", "2026-06-15 12:00:00+09");

		RetrospectResponse r = retrospectService.getRetrospect(userId, JULY);

		assertThat(r.yearMonth()).isEqualTo("2026-07");
		assertThat(r.confirmedCount()).isEqualTo(6); // 7/1,2,3,5,6,10 (DRAFT·6월 제외)
		assertThat(r.consecutiveDaysMax()).isEqualTo(3); // 7/1-2-3
		assertThat(r.resolutionSuccessCount()).isEqualTo(1);
		assertThat(r.coinEarned()).isEqualTo(260); // 10+200+50 (구매·6월 제외)

		// 감정 분포: JOY 3(7/1,2,6) · CALM 1(7/3) · 커스텀 '설레는' 1(7/5). 많은 순, JOY 선두.
		assertThat(r.emotions()).hasSize(3);
		EmotionStat top = r.emotions().get(0);
		assertThat(top.code()).isEqualTo("JOY");
		assertThat(top.labelKo()).isEqualTo("기쁨");
		assertThat(top.label()).isNull();
		assertThat(top.count()).isEqualTo(3);
		assertThat(r.emotions())
				.anySatisfy(e -> {
					assertThat(e.code()).isEqualTo("CALM");
					assertThat(e.labelKo()).isEqualTo("평온");
					assertThat(e.count()).isEqualTo(1);
				})
				.anySatisfy(e -> { // 직접 입력 감정 — code/labelKo 없이 label 만
					assertThat(e.code()).isNull();
					assertThat(e.labelKo()).isNull();
					assertThat(e.label()).isEqualTo("설레는");
					assertThat(e.count()).isEqualTo(1);
				});

		// 획득 아이템: 7월 HAT_CAP_BLACK 1건, MONKEY variant 이미지 해석됨
		assertThat(r.unlockedItems()).hasSize(1);
		UnlockedItem item = r.unlockedItems().get(0);
		assertThat(item.groupCode()).isEqualTo("HAT_CAP_BLACK");
		assertThat(item.nameKo()).isNotBlank();
		assertThat(item.imageUrl()).isNotNull(); // MONKEY 전용 variant 존재(V21)
	}

	// ===== ② 빈 달(기록 0건) — 깨지지 않고 빈 집계 =====

	@Test
	void 기록이_없는_달도_빈_집계로_정상_응답한다() {
		long userId = newUser();

		RetrospectResponse r = retrospectService.getRetrospect(userId, JULY);

		assertThat(r.yearMonth()).isEqualTo("2026-07");
		assertThat(r.confirmedCount()).isZero();
		assertThat(r.consecutiveDaysMax()).isZero();
		assertThat(r.resolutionSuccessCount()).isZero();
		assertThat(r.coinEarned()).isZero();
		assertThat(r.emotions()).isEmpty();
		assertThat(r.unlockedItems()).isEmpty();
	}

	// ===== ③ 연속일 리셋 — 하루 건너뛰면 1부터 다시 =====

	@Test
	void 최장_연속일은_하루라도_건너뛰면_끊긴다() {
		long userId = newUser();
		// 7/1 단독 → 7/3·7/4·7/5·7/6(연속 4) → 7/8 단독. 최장 = 4.
		newDiary(userId, "2026-07-01", "DONE", null, null);
		newDiary(userId, "2026-07-03", "DONE", null, null);
		newDiary(userId, "2026-07-04", "DONE", null, null);
		newDiary(userId, "2026-07-05", "DONE", null, null);
		newDiary(userId, "2026-07-06", "DONE", null, null);
		newDiary(userId, "2026-07-08", "DONE", null, null);

		RetrospectResponse r = retrospectService.getRetrospect(userId, JULY);

		assertThat(r.confirmedCount()).isEqualTo(6);
		assertThat(r.consecutiveDaysMax()).isEqualTo(4);
	}

	// ===== ④ IDOR: 타인 데이터는 절대 섞이지 않는다 =====

	@Test
	void 타인의_기록은_회고에_섞이지_않는다() {
		long owner = newUser();
		selectCharacterState(owner);
		newDiary(owner, "2026-07-01", "DONE", "JOY", null);
		newEvent(owner, "E_OWN", "DIARY_CONFIRM", 10, "2026-07-01 09:00:00+09");
		acquireItem(owner, "HAT_CAP_BLACK", "2026-07-01 12:00:00+09");

		long other = newUser();
		RetrospectResponse r = retrospectService.getRetrospect(other, JULY);

		// other 는 7월 데이터가 전혀 없다 — owner 의 것이 새어 나오면 안 된다.
		assertThat(r.confirmedCount()).isZero();
		assertThat(r.coinEarned()).isZero();
		assertThat(r.emotions()).isEmpty();
		assertThat(r.unlockedItems()).isEmpty();
	}

	private void selectCharacterState(long userId) {
		characterService.ensureState(userId);
		selectCharacter(userId, "MONKEY");
	}
}
