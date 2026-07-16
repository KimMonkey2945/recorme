package com.recordapp.domain.character;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.character.config.CharacterCoinProperties;
import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.dto.RewardResponse;
import com.recordapp.domain.character.service.CharacterRewardBackfillPoller;
import com.recordapp.domain.character.service.CharacterRewardService;
import com.recordapp.domain.character.service.CharacterService;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import java.time.LocalDate;
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
 * 보상 엔진(Task 028) 통합 테스트(Testcontainers PostgreSQL 18).
 *
 * <p>서비스 계층을 직접 호출해 <b>멱등 게이트·코인 적립·연속일 계산·연속/작심삼일 마일스톤·백스톱 폴러·
 * 보상함·리액션</b>이 실제 DB 에서 성립하는지 검증한다. 적립 트리거의 즉시 경로(diary/resolution →
 * AFTER_COMMIT @Async)는 비결정적이라 여기서 {@link CharacterRewardService} 를 직접 호출해 검증하고,
 * 백스톱 폴러 테스트가 "확정 기록 → 적립"의 종단 경로를 결정론적으로 커버한다.
 *
 * <p>⚠️ {@code @Transactional} 을 두지 않는다(CharacterServiceTest 동일) — 각 호출이 실제 커밋돼야
 * REQUIRES_NEW 격리·멱등 게이트가 의미를 갖는다. 사용자·기록은 JIT 프로비저닝/직접 INSERT 로 만든다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class CharacterRewardServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	CharacterRewardService rewardService;

	@Autowired
	CharacterService characterService;

	@Autowired
	CharacterRewardBackfillPoller backfillPoller;

	@Autowired
	CharacterCoinProperties coin;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

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

	/** 테스트용 기록 INSERT(FK 대상). status 로 확정 여부를 흉내낸다(DONE/PENDING=확정, DRAFT=미확정). */
	private long newDiary(long userId, LocalDate date, String status) {
		return jdbc().queryForObject(
				"INSERT INTO diaries (user_id, content, content_text, written_date, analysis_status) "
						+ "VALUES (?, '{\"ops\":[{\"insert\":\"오늘 하루\\n\"}]}', '오늘 하루', ?, ?) RETURNING id",
				Long.class, userId, date, status);
	}

	private int balance(long userId) {
		// 지갑 행이 아직 없는 사용자(JIT 미경유)도 0으로 견고하게 처리.
		Integer b = jdbc().queryForObject(
				"SELECT COALESCE((SELECT balance FROM user_wallets WHERE user_id = ?), 0)", Integer.class, userId);
		return b == null ? 0 : b;
	}

	private int eventCount(long userId) {
		Integer n = jdbc().queryForObject(
				"SELECT count(*) FROM character_events WHERE user_id = ?", Integer.class, userId);
		return n == null ? 0 : n;
	}

	private int eventCount(long userId, String eventKey) {
		Integer n = jdbc().queryForObject(
				"SELECT count(*) FROM character_events WHERE user_id = ? AND event_key = ?",
				Integer.class, userId, eventKey);
		return n == null ? 0 : n;
	}

	private int confirmedDiaryCount(long userId) {
		Integer n = jdbc().queryForObject(
				"SELECT confirmed_diary_count FROM user_progress WHERE user_id = ?", Integer.class, userId);
		return n == null ? 0 : n;
	}

	private int consecutiveDays(long userId) {
		Integer n = jdbc().queryForObject(
				"SELECT consecutive_days FROM user_progress WHERE user_id = ?", Integer.class, userId);
		return n == null ? 0 : n;
	}

	private String payloadLine(long userId, String eventKey) {
		return jdbc().queryForObject(
				"SELECT payload->>'line' FROM character_events WHERE user_id = ? AND event_key = ?",
				String.class, userId, eventKey);
	}

	// ===== ① 정상: 기록 확정 1회 =====

	@Test
	void diaryConfirm_creditsCoinAndProgress_exactlyOneEvent() {
		long userId = newUser();
		characterService.selectCharacter(userId, new com.recordapp.domain.character.dto.SelectCharacterRequest("MONKEY"));
		LocalDate day = LocalDate.of(2026, 7, 16);
		long diaryId = newDiary(userId, day, "DONE");

		rewardService.handleDiaryConfirmed(userId, diaryId, day);

		assertThat(balance(userId)).isEqualTo(coin.diary());
		assertThat(confirmedDiaryCount(userId)).isEqualTo(1);
		assertThat(consecutiveDays(userId)).isEqualTo(1);
		assertThat(eventCount(userId, "DIARY_CONFIRM:" + diaryId)).isEqualTo(1);
		// payload 에 대사가 항상 실린다(획득 대사 1줄 보장).
		assertThat(payloadLine(userId, "DIARY_CONFIRM:" + diaryId)).isNotBlank();
	}

	// ===== ② 멱등: 같은 이벤트 3회 재전달 → 전부 불변 =====

	@Test
	void diaryConfirm_reDelivered_isIdempotent() {
		long userId = newUser();
		LocalDate day = LocalDate.of(2026, 7, 16);
		long diaryId = newDiary(userId, day, "DONE");

		rewardService.handleDiaryConfirmed(userId, diaryId, day);
		rewardService.handleDiaryConfirmed(userId, diaryId, day);
		rewardService.handleDiaryConfirmed(userId, diaryId, day);

		assertThat(balance(userId)).as("코인 1회만").isEqualTo(coin.diary());
		assertThat(confirmedDiaryCount(userId)).as("진척 1회만").isEqualTo(1);
		assertThat(eventCount(userId)).as("이벤트 정확히 1행").isEqualTo(1);
	}

	// ===== ⑧ 연속일: 연속 +1 / 건너뛰면 1 리셋 / 같은 날 재확정 불변 =====

	@Test
	void consecutiveDays_incrementsResetsAndStaysOnSameDay() {
		long userId = newUser();
		LocalDate d1 = LocalDate.of(2026, 7, 1);
		LocalDate d2 = LocalDate.of(2026, 7, 2);
		LocalDate d4 = LocalDate.of(2026, 7, 4); // 하루 건너뜀

		long id1 = newDiary(userId, d1, "DONE");
		long id2 = newDiary(userId, d2, "DONE");
		long id4 = newDiary(userId, d4, "DONE");

		rewardService.handleDiaryConfirmed(userId, id1, d1);
		assertThat(consecutiveDays(userId)).isEqualTo(1);

		rewardService.handleDiaryConfirmed(userId, id2, d2);
		assertThat(consecutiveDays(userId)).as("연속 → +1").isEqualTo(2);

		// 같은 날 재확정(같은 diaryId 재전달) → 게이트가 막아 진척 불변.
		rewardService.handleDiaryConfirmed(userId, id2, d2);
		assertThat(consecutiveDays(userId)).as("같은 날 재확정 불변").isEqualTo(2);
		assertThat(confirmedDiaryCount(userId)).isEqualTo(2);

		rewardService.handleDiaryConfirmed(userId, id4, d4);
		assertThat(consecutiveDays(userId)).as("하루 건너뜀 → 1 리셋").isEqualTo(1);
		assertThat(confirmedDiaryCount(userId)).isEqualTo(3);
	}

	// ===== 소급(과거) 확정: 진행 중인 연속 기록을 리셋하지 않는다 =====

	@Test
	void consecutiveDays_backdatedConfirm_doesNotResetStreak() {
		long userId = newUser();
		// 07-06~07-10 5일 연속 확정 → streak=5.
		for (int i = 0; i < 5; i++) {
			LocalDate day = LocalDate.of(2026, 7, 6).plusDays(i);
			rewardService.handleDiaryConfirmed(userId, newDiary(userId, day, "DONE"), day);
		}
		assertThat(consecutiveDays(userId)).isEqualTo(5);

		// 빼먹었던 과거 날짜(07-03)를 뒤늦게 확정 — 현재 스트릭(5)을 건드리면 안 된다.
		LocalDate backdated = LocalDate.of(2026, 7, 3);
		rewardService.handleDiaryConfirmed(userId, newDiary(userId, backdated, "DONE"), backdated);
		assertThat(consecutiveDays(userId)).as("소급 확정은 스트릭 불변").isEqualTo(5);
		assertThat(confirmedDiaryCount(userId)).as("누적 수는 +1").isEqualTo(6);

		// 다음 날(07-11) 확정 → 정상적으로 6일째로 이어진다(소급이 오염시키지 않았다).
		LocalDate next = LocalDate.of(2026, 7, 11);
		rewardService.handleDiaryConfirmed(userId, newDiary(userId, next, "DONE"), next);
		assertThat(consecutiveDays(userId)).as("소급 후에도 연속 이어짐").isEqualTo(6);
	}

	// ===== 연속 마일스톤: 7일 도달 시 계정당 1회 =====

	@Test
	void streakMilestone_grantedOnceAtThreshold() {
		long userId = newUser();
		int expectedMilestone = coin.streakCoin(7);
		assertThat(expectedMilestone).as("테스트 전제: streak 7 마일스톤 설정됨").isGreaterThan(0);

		// 7일 연속 확정.
		for (int i = 0; i < 7; i++) {
			LocalDate day = LocalDate.of(2026, 6, 1).plusDays(i);
			long id = newDiary(userId, day, "DONE");
			rewardService.handleDiaryConfirmed(userId, id, day);
		}

		assertThat(consecutiveDays(userId)).isEqualTo(7);
		assertThat(eventCount(userId, "STREAK:7")).as("마일스톤 이벤트 1행").isEqualTo(1);
		// 잔액 = 기록 7회 + 연속 7일 마일스톤.
		assertThat(balance(userId)).isEqualTo(coin.diary() * 7 + expectedMilestone);

		// 8일차 확정해도 STREAK:7 재지급 없음(게이트).
		LocalDate d8 = LocalDate.of(2026, 6, 8);
		long id8 = newDiary(userId, d8, "DONE");
		rewardService.handleDiaryConfirmed(userId, id8, d8);
		assertThat(eventCount(userId, "STREAK:7")).isEqualTo(1);
	}

	// ===== 작심삼일: 1·2일차 부분 보상 + 완주 =====

	@Test
	void resolutionProgress_creditsDaysAndCompletion() {
		long userId = newUser();
		long resolutionId = 777L; // character_events 는 resolutions FK 가 없어 임의 id 로 검증 가능

		rewardService.handleResolutionProgress(userId, resolutionId, 1, false, 1);
		assertThat(balance(userId)).isEqualTo(coin.resolutionDay1());

		rewardService.handleResolutionProgress(userId, resolutionId, 2, false, 1);
		assertThat(balance(userId)).isEqualTo(coin.resolutionDay1() + coin.resolutionDay2());

		rewardService.handleResolutionProgress(userId, resolutionId, 3, true, 1);
		assertThat(balance(userId))
				.isEqualTo(coin.resolutionDay1() + coin.resolutionDay2() + coin.resolutionComplete());

		// 완주 진척 갱신 확인.
		Integer successCount = jdbc().queryForObject(
				"SELECT resolution_success_count FROM user_progress WHERE user_id = ?", Integer.class, userId);
		assertThat(successCount).isEqualTo(1);

		// 재전달 멱등: 완주 이벤트 다시 보내도 불변.
		rewardService.handleResolutionProgress(userId, resolutionId, 3, true, 1);
		assertThat(balance(userId))
				.isEqualTo(coin.resolutionDay1() + coin.resolutionDay2() + coin.resolutionComplete());
		assertThat(eventCount(userId, "RESOLUTION_SUCCESS:" + resolutionId)).isEqualTo(1);
	}

	// ===== 출석: 하루 1회 =====

	@Test
	void attendance_grantedOncePerDay() {
		long userId = newUser();
		LocalDate day = LocalDate.of(2026, 7, 16);

		CharacterRewardService.AttendanceResult first = rewardService.grantAttendance(userId, day);
		assertThat(first.granted()).isTrue();
		assertThat(first.balance()).isEqualTo(coin.attendance());

		CharacterRewardService.AttendanceResult second = rewardService.grantAttendance(userId, day);
		assertThat(second.granted()).as("오늘 이미 출석").isFalse();
		assertThat(balance(userId)).as("중복 적립 없음").isEqualTo(coin.attendance());

		CharacterRewardService.AttendanceResult nextDay = rewardService.grantAttendance(userId, day.plusDays(1));
		assertThat(nextDay.granted()).isTrue();
		assertThat(balance(userId)).isEqualTo(coin.attendance() * 2);
	}

	// ===== ⑥ 백스톱 폴러: 유실분 보정(1회만) =====

	@Test
	void backfillPoller_creditsLostConfirmations_onlyOnce() {
		long userId = newUser();
		LocalDate day = LocalDate.of(2026, 7, 10);
		// 리스너 유실 시뮬레이션: 확정된 기록만 있고 character_events 는 없다.
		long diaryId = newDiary(userId, day, "DONE");
		assertThat(eventCount(userId)).isZero();

		backfillPoller.backfill();

		assertThat(balance(userId)).as("폴러가 보정 적립").isEqualTo(coin.diary());
		assertThat(eventCount(userId, "DIARY_CONFIRM:" + diaryId)).isEqualTo(1);

		// 다시 돌려도 게이트가 막아 중복 없음.
		backfillPoller.backfill();
		assertThat(balance(userId)).isEqualTo(coin.diary());
		assertThat(eventCount(userId, "DIARY_CONFIRM:" + diaryId)).isEqualTo(1);
	}

	@Test
	void backfillPoller_ignoresDraftDiaries() {
		long userId = newUser();
		LocalDate day = LocalDate.of(2026, 7, 11);
		// 미확정(DRAFT) 기록 — 확정된 적 없으므로 적립 대상이 아니다(롤백/미확정에 코인이 붙지 않음).
		newDiary(userId, day, "DRAFT");

		backfillPoller.backfill();

		assertThat(balance(userId)).isZero();
		assertThat(eventCount(userId)).isZero();
	}

	// ===== 보상함 + ack =====

	@Test
	void rewardsInbox_listAndAck() {
		long userId = newUser();
		LocalDate day = LocalDate.of(2026, 7, 16);
		long diaryId = newDiary(userId, day, "DONE");
		rewardService.handleDiaryConfirmed(userId, diaryId, day);
		rewardService.grantAttendance(userId, day);

		PageResponse<RewardResponse> rewards = rewardService.getRewards(userId, new CursorRequest(null, 20));
		assertThat(rewards.items()).as("미확인 보상 2건(기록+출석)").hasSize(2);
		assertThat(rewardService.getWallet(userId).unackedRewardCount()).isEqualTo(2);

		// 확정 리액션 조회(폴링 불필요).
		RewardResponse reaction = rewardService.getReaction(userId, diaryId);
		assertThat(reaction).isNotNull();
		assertThat(reaction.coinDelta()).isEqualTo(coin.diary());
		assertThat(reaction.payload().get("line").asText()).isNotBlank();

		// 전체 확인 → 미확인 0.
		assertThat(rewardService.ackRewards(userId).acked()).isEqualTo(2);
		assertThat(rewardService.getWallet(userId).unackedRewardCount()).isZero();
		assertThat(rewardService.getRewards(userId, new CursorRequest(null, 20)).items()).isEmpty();
	}

	// ===== IDOR: 적립·조회가 userId 로 격리 =====

	@Test
	void rewards_isolatedByUser() {
		long owner = newUser();
		long other = newUser();
		LocalDate day = LocalDate.of(2026, 7, 16);
		long diaryId = newDiary(owner, day, "DONE");
		rewardService.handleDiaryConfirmed(owner, diaryId, day);

		assertThat(balance(owner)).isEqualTo(coin.diary());
		assertThat(rewardService.getWallet(other).balance()).isZero();
		assertThat(rewardService.getRewards(other, new CursorRequest(null, 20)).items()).isEmpty();
	}

	// ===== 상점 구매(코인 소비) =====

	private static final String HAT = "HAT_CAP_BLACK"; // V21 시드 — COIN 15

	/** 지갑에 코인을 심는다(ensureState 로 지갑 행 보장 후 잔액 설정). */
	private void seedCoins(long userId, int amount) {
		characterService.ensureState(userId);
		jdbc().update("UPDATE user_wallets SET balance = ? WHERE user_id = ?", amount, userId);
	}

	private boolean owns(long userId, String groupCode) {
		Integer n = jdbc().queryForObject(
				"SELECT count(*) FROM user_item_groups WHERE user_id = ? AND group_code = ?",
				Integer.class, userId, groupCode);
		return n != null && n > 0;
	}

	@Test
	void purchase_deductsCoinAndGrantsOwnership() {
		long userId = newUser();
		seedCoins(userId, 100);

		MyCharacterResponse me = rewardService.purchase(userId, HAT);

		assertThat(balance(userId)).as("100 - 15").isEqualTo(85);
		assertThat(me.coinBalance()).isEqualTo(85);
		assertThat(owns(userId, HAT)).isTrue();
		// 구매 원장은 미확인 보상 배지에 잡히지 않는다(즉시 ack).
		assertThat(rewardService.getWallet(userId).unackedRewardCount()).isZero();
		assertThat(eventCount(userId, "PURCHASE:" + HAT)).isEqualTo(1);
	}

	@Test
	void purchase_insufficientCoin_throwsAndRollsBack() {
		long userId = newUser();
		seedCoins(userId, 10); // 가격 15 미만

		assertThatThrownBy(() -> rewardService.purchase(userId, HAT))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.COIN_INSUFFICIENT));

		// 잔액 불변 + 미소유 + 게이트 미잔존(재시도 가능).
		assertThat(balance(userId)).isEqualTo(10);
		assertThat(owns(userId, HAT)).isFalse();
		assertThat(eventCount(userId, "PURCHASE:" + HAT)).isZero();

		// 코인을 모아 재구매하면 성공한다.
		seedCoins(userId, 20);
		rewardService.purchase(userId, HAT);
		assertThat(owns(userId, HAT)).isTrue();
		assertThat(balance(userId)).isEqualTo(5);
	}

	@Test
	void purchase_alreadyOwned_isNoCharge() {
		long userId = newUser();
		seedCoins(userId, 100);
		rewardService.purchase(userId, HAT);
		assertThat(balance(userId)).isEqualTo(85);

		// 재구매 시도 → 무과금(이미 보유).
		rewardService.purchase(userId, HAT);
		assertThat(balance(userId)).as("재구매 무과금").isEqualTo(85);
		assertThat(eventCount(userId, "PURCHASE:" + HAT)).isEqualTo(1);
	}

	@Test
	void purchase_unknownGroup_throwsValidationError() {
		long userId = newUser();
		seedCoins(userId, 100);

		assertThatThrownBy(() -> rewardService.purchase(userId, "NO_SUCH_GROUP"))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.VALIDATION_ERROR));
		assertThat(balance(userId)).isEqualTo(100);
	}
}
