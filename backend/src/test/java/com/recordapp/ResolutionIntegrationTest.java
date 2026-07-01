package com.recordapp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.device.dto.RegisterDeviceTokenRequest;
import com.recordapp.domain.device.mapper.DeviceTokenMapper;
import com.recordapp.domain.device.service.DeviceTokenService;
import com.recordapp.domain.device.vo.DevicePlatform;
import com.recordapp.domain.resolution.dto.CreateResolutionRequest;
import com.recordapp.domain.resolution.dto.ExtendResolutionRequest;
import com.recordapp.domain.resolution.dto.ResolutionCalendarDay;
import com.recordapp.domain.resolution.dto.ResolutionCheckView;
import com.recordapp.domain.resolution.dto.ResolutionDetailResponse;
import com.recordapp.domain.resolution.dto.ResolutionListItem;
import com.recordapp.domain.resolution.mapper.ResolutionMapper;
import com.recordapp.domain.resolution.service.ResolutionBatchTx;
import com.recordapp.domain.resolution.service.ResolutionService;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
 * 작심삼일(resolution) 도메인 런타임 검증 통합 테스트(Testcontainers PostgreSQL 18).
 *
 * <p>서비스 계층({@link ResolutionService}/{@link ResolutionBatchTx})을 직접 호출해 HTTP·인증을 우회하고,
 * 매퍼/동적SQL/resultMap constructor 매핑/상태 전이가 <b>실제 DB</b>에서 정확히 동작하는지 검증한다.
 * 사용자 식별은 기존 통합테스트 관례대로 JIT 프로비저닝으로 users 행을 만들어 내부 userId 를 확보한다.
 *
 * <p>날짜는 서비스와 동일하게 KST(Asia/Seoul) 벽시계 기준으로 상대(오늘/어제/내일) 구성한다.
 * 과거 시작 결심은 서비스 생성이 막으므로(@FutureOrPresent + 서비스 재검증) JdbcTemplate 으로 직접 심는다.
 *
 * <p>⚠️ 클래스/메서드에 {@code @Transactional}을 두지 않는다(DiaryIntegrationTest 동일). 완료 체크 SUCCESS 훅의
 * afterCommit 푸시·서비스 커밋 가시성이 트랜잭션 롤백에 가려지지 않도록 각 서비스 호출이 실제 커밋되게 한다.
 * 스케줄러(@Scheduled)는 test 프로파일에서 cron="-" 로 꺼 두고, 배치는 {@link ResolutionBatchTx} 를 직접 호출한다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class ResolutionIntegrationTest {

	private static final ZoneId KST = ZoneId.of("Asia/Seoul");

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	ResolutionService resolutionService;

	@Autowired
	ResolutionBatchTx batchTx;

	@Autowired
	ResolutionMapper resolutionMapper;

	@Autowired
	DeviceTokenService deviceTokenService;

	@Autowired
	DeviceTokenMapper deviceTokenMapper;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	// ===== 헬퍼 =====

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	/** KST 벽시계 기준 오늘(서비스가 보는 '오늘'과 일치). */
	private LocalDate today() {
		return LocalDate.now(KST);
	}

	/** JIT 프로비저닝으로 회원 1명 생성 후 내부 PK 반환(테스트별 고유 uid → userId 격리). */
	private long newUser() {
		String sub = UUID.randomUUID().toString();
		return provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", "tester"), Map.of("sub", sub)))
				.userId();
	}

	private CreateResolutionRequest createReq(String title, LocalDate start) {
		return new CreateResolutionRequest(title, start, null);
	}

	private String resolutionStatus(long id) {
		return jdbc().queryForObject("SELECT status FROM resolutions WHERE id = ?", String.class, id);
	}

	private String streakGroupId(long id) {
		return jdbc().queryForObject("SELECT streak_group_id::text FROM resolutions WHERE id = ?", String.class, id);
	}

	private String checkStatusByDay(long resolutionId, int dayIndex) {
		return jdbc().queryForObject(
				"SELECT status FROM resolution_checks WHERE resolution_id = ? AND day_index = ?",
				String.class, resolutionId, dayIndex);
	}

	private int doneCheckCount(long resolutionId) {
		Integer n = jdbc().queryForObject(
				"SELECT count(*) FROM resolution_checks WHERE resolution_id = ? AND status = 'DONE'",
				Integer.class, resolutionId);
		return n == null ? 0 : n;
	}

	/** 과거 시작 결심을 직접 심는다(서비스 검증 우회). end_date = start+2(span CHECK). streak_seq=1. */
	private long insertResolutionRow(long userId, String title, LocalDate start, String status) {
		return jdbc().queryForObject(
				"INSERT INTO resolutions (user_id, title, start_date, end_date, status, streak_seq) "
						+ "VALUES (?, ?, ?, ?, ?, 1) RETURNING id",
				Long.class, userId, title, java.sql.Date.valueOf(start),
				java.sql.Date.valueOf(start.plusDays(2)), status);
	}

	/** 일별 체크 1행 직접 심기. DONE 이면 completed_at 세팅(chk_resolution_checks_done 충족). */
	private void insertCheckRow(long resolutionId, long userId, LocalDate date, int dayIndex, String status) {
		if ("DONE".equals(status)) {
			jdbc().update(
					"INSERT INTO resolution_checks (resolution_id, user_id, check_date, day_index, status, completed_at) "
							+ "VALUES (?, ?, ?, ?, 'DONE', now())",
					resolutionId, userId, java.sql.Date.valueOf(date), dayIndex);
		} else {
			jdbc().update(
					"INSERT INTO resolution_checks (resolution_id, user_id, check_date, day_index, status) "
							+ "VALUES (?, ?, ?, ?, ?)",
					resolutionId, userId, java.sql.Date.valueOf(date), dayIndex, status);
		}
	}

	// ===== 1) 생성: 결심 1행 + 체크 3행 프리생성 =====

	@Test
	void create_preCreatesThreeChecks() {
		long userId = newUser();
		LocalDate start = today();

		ResolutionDetailResponse detail = resolutionService.create(userId, createReq("물 마시기", start));

		// 헤더: 3일 span, ONGOING, 1연속(streakSeq=1).
		assertThat(detail.startDate()).isEqualTo(start);
		assertThat(detail.endDate()).isEqualTo(start.plusDays(2));
		assertThat(detail.status()).isEqualTo("ONGOING");
		assertThat(detail.streakSeq()).isEqualTo((short) 1);

		// 체크 3행: day_index 1/2/3, check_date=start+0/1/2, 전부 PENDING·미완료.
		List<ResolutionCheckView> checks = detail.checks();
		assertThat(checks).hasSize(3);
		assertThat(checks).extracting(ResolutionCheckView::dayIndex)
				.containsExactly((short) 1, (short) 2, (short) 3);
		assertThat(checks).extracting(ResolutionCheckView::checkDate)
				.containsExactly(start, start.plusDays(1), start.plusDays(2));
		assertThat(checks).extracting(ResolutionCheckView::status)
				.containsExactly("PENDING", "PENDING", "PENDING");
		assertThat(checks).allSatisfy(c -> assertThat(c.completedAt()).isNull());

		// streak_group_id 새 체인 생성(gen_random_uuid).
		assertThat(streakGroupId(detail.id())).isNotBlank();
	}

	// ===== 2) 완료 멱등: completeToday 2회 → DONE 1행, 예외 없음 =====

	@Test
	void completeToday_isIdempotent() {
		long userId = newUser();
		long id = resolutionService.create(userId, createReq("스트레칭", today())).id();

		// 1회차: 오늘(1일차) 체크 DONE 전이.
		ResolutionDetailResponse first = resolutionService.completeToday(userId, id);
		// 2회차: 이미 DONE → 멱등 통과(예외 없음).
		ResolutionDetailResponse second = resolutionService.completeToday(userId, id);

		assertThat(second.status()).isEqualTo("ONGOING"); // 아직 1일차만 완료 → 진행 중.
		assertThat(doneCheckCount(id)).as("중복 완료해도 DONE 은 1행").isEqualTo(1);

		ResolutionCheckView day1 = first.checks().get(0);
		assertThat(day1.status()).isEqualTo("DONE");
		assertThat(day1.completedAt()).as("DONE 전이 시 완료시각 세팅").isNotNull();
		// 나머지 2일차는 여전히 PENDING.
		assertThat(second.checks().get(1).status()).isEqualTo("PENDING");
		assertThat(second.checks().get(2).status()).isEqualTo("PENDING");
	}

	// ===== 3) SUCCESS 전이: 3일 완주 시 조건부 1회 전이(멱등) =====

	@Test
	void markSuccessIfAllDone_transitionsExactlyOnce() {
		long userId = newUser();
		long id = resolutionService.create(userId, createReq("운동", today())).id();

		// 오늘(1일차)만 서비스로 완료 → 아직 미완주라 ONGOING 유지.
		resolutionService.completeToday(userId, id);
		assertThat(resolutionStatus(id)).isEqualTo("ONGOING");

		// 나머지 2·3일차를 직접 DONE 처리(하루씩 지날 것을 시뮬레이션).
		jdbc().update("UPDATE resolution_checks SET status='DONE', completed_at=now() "
				+ "WHERE resolution_id = ? AND day_index IN (2,3)", id);

		// 조건부 전이: 3일 모두 DONE → 정확히 1행 SUCCESS.
		assertThat(resolutionMapper.markResolutionSuccessIfAllDone(id)).as("최초 전이 1행").isEqualTo(1);
		assertThat(resolutionStatus(id)).isEqualTo("SUCCESS");
		// 재호출은 status='ONGOING' 가드로 0행(멱등).
		assertThat(resolutionMapper.markResolutionSuccessIfAllDone(id)).as("재호출 0행(멱등)").isEqualTo(0);
		assertThat(resolutionStatus(id)).isEqualTo("SUCCESS");
	}

	// ===== 4) 자정 실패 배치: 초과 PENDING → MISSED + 결심 FAILED, 오늘 체크·비ONGOING 불변 =====

	@Test
	void failOverdueBatch_missesOverdueAndFailsResolution() {
		long userId = newUser();
		LocalDate today = today();

		// R1: ONGOING, 어제·그저께가 미완료(overdue), 오늘 체크는 아직 유효.
		long r1 = insertResolutionRow(userId, "일찍 자기", today.minusDays(2), "ONGOING");
		insertCheckRow(r1, userId, today.minusDays(2), 1, "PENDING");
		insertCheckRow(r1, userId, today.minusDays(1), 2, "PENDING");
		insertCheckRow(r1, userId, today, 3, "PENDING");

		// R2: 이미 FAILED(터미널) — 과거 PENDING 체크가 있어도 배치는 건드리지 않아야 한다(r.status='ONGOING' 필터).
		long r2 = insertResolutionRow(userId, "이미 실패", today.minusDays(2), "FAILED");
		insertCheckRow(r2, userId, today.minusDays(2), 1, "PENDING");

		// 배치 드레인(다른 테스트의 잔여 overdue 와 무관하게, 남은 게 없을 때까지 반복).
		Set<Long> newlyFailed = new HashSet<>();
		ResolutionBatchTx.FailureBatch batch;
		do {
			batch = batchTx.failOverdueBatch(today, 100);
			batch.newlyFailed().forEach(c -> newlyFailed.add(c.resolutionId()));
		} while (batch.fetched() > 0);

		// R1: overdue(1·2일차) → MISSED, 오늘(3일차)은 불변, 결심 FAILED.
		assertThat(checkStatusByDay(r1, 1)).isEqualTo("MISSED");
		assertThat(checkStatusByDay(r1, 2)).isEqualTo("MISSED");
		assertThat(checkStatusByDay(r1, 3)).as("오늘 체크는 실패 배치 대상 아님").isEqualTo("PENDING");
		assertThat(resolutionStatus(r1)).isEqualTo("FAILED");
		assertThat(newlyFailed).as("R1 이 이번 배치에서 ONGOING→FAILED 확정").contains(r1);

		// R2: 비ONGOING 이라 과거 PENDING 체크·상태 모두 불변.
		assertThat(checkStatusByDay(r2, 1)).as("FAILED 결심의 과거 체크는 불변").isEqualTo("PENDING");
		assertThat(resolutionStatus(r2)).isEqualTo("FAILED");

		// 완전 드레인 직후 재실행은 0건(멱등).
		assertThat(batchTx.failOverdueBatch(today, 100).fetched()).isEqualTo(0);
	}

	// ===== 5) 미래 시작 제외: 모든 check_date>오늘 → 실패 배치 대상 아님 =====

	@Test
	void failOverdueBatch_excludesFutureStart() {
		long userId = newUser();
		LocalDate today = today();

		// 서비스로 내일 시작 결심 생성(미래 시작 허용). 모든 체크가 내일 이후.
		long id = resolutionService.create(userId, createReq("내일부터", today.plusDays(1))).id();

		batchTx.failOverdueBatch(today, 100); // 전역 배치 실행(미래 결심은 대상 아님).

		assertThat(resolutionStatus(id)).as("미래 시작 결심은 실패하지 않음").isEqualTo("ONGOING");
		assertThat(checkStatusByDay(id, 1)).isEqualTo("PENDING");
		assertThat(checkStatusByDay(id, 2)).isEqualTo("PENDING");
		assertThat(checkStatusByDay(id, 3)).isEqualTo("PENDING");
	}

	// ===== 6) 연장: SUCCESS 결심의 다음 3일을 같은 체인으로 신규 생성 + 이중/비성공 연장 차단 =====

	@Test
	void extend_createsNextChainAndBlocksInvalid() {
		long userId = newUser();
		LocalDate today = today();

		// 성공한 결심 준비: 생성 후 3일 모두 DONE → SUCCESS 전이.
		long prevId = resolutionService.create(userId, createReq("아침 러닝", today)).id();
		jdbc().update("UPDATE resolution_checks SET status='DONE', completed_at=now() WHERE resolution_id = ?", prevId);
		assertThat(resolutionMapper.markResolutionSuccessIfAllDone(prevId)).isEqualTo(1);
		String chain = streakGroupId(prevId);

		// 연장: 같은 체인, streakSeq=2, 시작=max(prev.end+1, today)=오늘+3, 체크 3행 프리생성.
		ResolutionDetailResponse extended = resolutionService.extend(userId, prevId, new ExtendResolutionRequest(null));
		assertThat(extended.streakSeq()).isEqualTo((short) 2);
		assertThat(extended.startDate()).isEqualTo(today.plusDays(3));
		assertThat(extended.endDate()).isEqualTo(today.plusDays(5));
		assertThat(extended.checks()).hasSize(3);
		assertThat(extended.checks()).extracting(ResolutionCheckView::status)
				.containsExactly("PENDING", "PENDING", "PENDING");
		assertThat(streakGroupId(extended.id())).as("연장은 같은 streak 체인 승계").isEqualTo(chain);
		assertThat(extended.title()).isEqualTo("아침 러닝"); // 제목 승계.

		// 이중 연장: 같은 결심을 다시 연장 → uq(streak_group_id, streak_seq) 선검사로 차단.
		assertThatThrownBy(() -> resolutionService.extend(userId, prevId, new ExtendResolutionRequest(null)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.RESOLUTION_ALREADY_EXTENDED));

		// 비성공(ONGOING) 결심 연장 → RESOLUTION_NOT_EXTENDABLE.
		long ongoingId = resolutionService.create(userId, createReq("진행중", today)).id();
		assertThatThrownBy(() -> resolutionService.extend(userId, ongoingId, new ExtendResolutionRequest(null)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.RESOLUTION_NOT_EXTENDABLE));
	}

	// ===== 7) 소유권(IDOR): 타인 userId 접근은 모두 RESOLUTION_NOT_FOUND =====

	@Test
	void authz_otherUserCannotAccess() {
		long owner = newUser();
		long other = newUser();
		long id = resolutionService.create(owner, createReq("비밀 결심", today())).id();

		assertThatThrownBy(() -> resolutionService.getDetail(other, id))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.RESOLUTION_NOT_FOUND));
		assertThatThrownBy(() -> resolutionService.completeToday(other, id))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.RESOLUTION_NOT_FOUND));
		assertThatThrownBy(() -> resolutionService.cancel(other, id))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.RESOLUTION_NOT_FOUND));

		// 소유자 데이터는 온전.
		assertThat(resolutionService.getDetail(owner, id).title()).isEqualTo("비밀 결심");
	}

	// ===== 8) 캘린더/목록: resultMap constructor 매핑 + dayStatuses + 커서 페이징 =====

	@Test
	void calendarAndList_mapAndPageCorrectly() {
		long userId = newUser();
		LocalDate today = today();

		// 결심 3건 생성(모두 오늘 시작 → dayStatuses 초기 PENDING,PENDING,PENDING).
		long id1 = resolutionService.create(userId, createReq("결심1", today)).id();
		long id2 = resolutionService.create(userId, createReq("결심2", today)).id();
		long id3 = resolutionService.create(userId, createReq("결심3", today)).id();

		// --- 캘린더: 이번 달(오늘 기준)에 최소 오늘자 체크 3건(결심 3개)이 매핑되어야 한다. ---
		String yearMonth = String.format("%04d-%02d", today.getYear(), today.getMonthValue());
		List<ResolutionCalendarDay> calendar = resolutionService.getCalendar(userId, yearMonth);
		List<ResolutionCalendarDay> todayEntries = calendar.stream()
				.filter(d -> d.date().equals(today)).toList();
		assertThat(todayEntries).as("오늘자 (날짜,결심) 3행 매핑").hasSize(3);
		assertThat(todayEntries).allSatisfy(d -> {
			assertThat(d.resolutionStatus()).isEqualTo("ONGOING");
			assertThat(d.checkStatus()).isEqualTo("PENDING");
			assertThat(d.title()).isNotBlank();
		});

		// --- 목록: 커서 페이징(size=2 → 2건 + hasNext, 다음 페이지 1건). id DESC 최신순. ---
		PageResponse<ResolutionListItem> first = resolutionService.getList(userId, null, new CursorRequest(null, 2));
		assertThat(first.items()).hasSize(2);
		assertThat(first.hasNext()).isTrue();
		assertThat(first.nextCursor()).isNotNull();
		assertThat(first.items().get(0).id()).isEqualTo(id3); // 최신(id 최대) 우선.
		// dayStatuses: day_index 순 콤마 결합(신규는 전부 PENDING).
		assertThat(first.items().get(0).dayStatuses()).isEqualTo("PENDING,PENDING,PENDING");

		PageResponse<ResolutionListItem> second =
				resolutionService.getList(userId, null, new CursorRequest(first.nextCursor(), 2));
		assertThat(second.items()).hasSize(1);
		assertThat(second.items().get(0).id()).isEqualTo(id1);
		assertThat(second.hasNext()).isFalse();
		// 페이지 간 중복 없음.
		assertThat(second.items()).extracting(ResolutionListItem::id)
				.doesNotContainAnyElementsOf(first.items().stream().map(ResolutionListItem::id).toList());

		// --- status 필터: SUCCESS 탭은 아직 비어 있음. ---
		PageResponse<ResolutionListItem> successTab =
				resolutionService.getList(userId, "SUCCESS", new CursorRequest(null, 10));
		assertThat(successTab.items()).isEmpty();

		// id2 를 SUCCESS 로 만든 뒤 필터가 정확히 1건 반환하는지.
		jdbc().update("UPDATE resolution_checks SET status='DONE', completed_at=now() WHERE resolution_id = ?", id2);
		resolutionMapper.markResolutionSuccessIfAllDone(id2);
		PageResponse<ResolutionListItem> ongoingTab =
				resolutionService.getList(userId, "ONGOING", new CursorRequest(null, 10));
		assertThat(ongoingTab.items()).extracting(ResolutionListItem::id)
				.containsExactlyInAnyOrder(id1, id3).doesNotContain(id2);
	}

	// ===== 9) 디바이스 토큰: upsert 멱등 + 소유 이전 + 팬아웃 조회 =====

	@Test
	void deviceToken_upsertTransfersOwnership() {
		long userA = newUser();
		long userB = newUser();
		String token = "fcm-" + UUID.randomUUID();

		// userA 등록 → 조회에 노출.
		deviceTokenService.register(userA, new RegisterDeviceTokenRequest(token, DevicePlatform.ANDROID));
		assertThat(deviceTokenMapper.findTokensByUserId(userA)).contains(token);

		// 같은 토큰 재등록(멱등) → 여전히 1행.
		deviceTokenService.register(userA, new RegisterDeviceTokenRequest(token, DevicePlatform.ANDROID));
		assertThat(tokenRowCount(token)).as("같은 토큰 재등록은 1행 유지").isEqualTo(1);

		// userB 가 같은 토큰 등록 → 소유 이전(전역 유니크 upsert).
		deviceTokenService.register(userB, new RegisterDeviceTokenRequest(token, DevicePlatform.IOS));
		assertThat(tokenRowCount(token)).isEqualTo(1);
		assertThat(deviceTokenMapper.findTokensByUserId(userB)).contains(token);
		assertThat(deviceTokenMapper.findTokensByUserId(userA)).as("소유 이전 후 이전 사용자에겐 미노출")
				.doesNotContain(token);
	}

	private int tokenRowCount(String token) {
		Integer n = jdbc().queryForObject(
				"SELECT count(*) FROM device_tokens WHERE token = ?", Integer.class, token);
		return n == null ? 0 : n;
	}
}
