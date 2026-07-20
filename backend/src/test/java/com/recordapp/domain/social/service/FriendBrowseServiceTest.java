package com.recordapp.domain.social.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.diary.dto.FriendDiarySummaryDay;
import com.recordapp.domain.resolution.dto.ResolutionListItem;
import com.recordapp.domain.social.dto.FriendCharacterResponse;
import com.recordapp.domain.social.dto.FriendDiarySummaryResponse;
import com.recordapp.domain.social.dto.SendFriendRequest;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
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
 * FriendBrowseService 통합 테스트(Testcontainers PostgreSQL 18).
 *
 * <p>검증 축은 둘이다: ① <b>권한 게이트</b> — 수락된 친구가 아닌 모든 경우(친구아님·대기중·차단·탈퇴·
 * 없는 uuid·잘못된 형식·자기 자신)가 예외 없이 404 로 은닉되는지. ② <b>노출 범위</b> — 캘린더에서
 * PRIVATE·DRAFT 가 빠지고, 캐릭터 조회가 대상의 상태 행을 만들지 않는지(ensureState 미호출 회귀 방어).
 *
 * <p>클래스에 @Transactional 을 두지 않는다 — 각 호출이 실제로 커밋돼야 "상태 행이 생기지 않았다"는
 * 단언이 의미를 갖는다(기존 CharacterServiceTest·FriendServiceTest 와 동일 관례).
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class FriendBrowseServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	FriendBrowseService friendBrowseService;

	@Autowired
	FriendService friendService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	// ===== 헬퍼 =====

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	private long newUser(String nickname) {
		String sub = UUID.randomUUID().toString();
		return provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", nickname),
						Map.of("sub", sub))).userId();
	}

	private String uuidOf(long userId) {
		return jdbc().queryForObject("SELECT uuid::text FROM users WHERE id = ?", String.class, userId);
	}

	/** A↔B 를 수락된 친구로 만든다. */
	private void makeFriends(long a, long b) {
		friendService.sendRequest(a, new SendFriendRequest(null, uuidOf(b)));
		Long requestId = jdbc().queryForObject(
				"SELECT id FROM friendships WHERE requester_id = ? AND addressee_id = ?",
				Long.class, a, b);
		friendService.accept(b, requestId);
	}

	/** 확정 기록 1건 삽입(visibility 지정). analysis_status=DONE. */
	private void insertDiary(long userId, String date, String visibility) {
		jdbc().update("""
				INSERT INTO diaries (user_id, content, content_text, written_date,
				                     analysis_status, visibility, primary_emotion)
				VALUES (?, '{"ops":[]}'::jsonb, '내용', ?::date, 'DONE', ?, 'JOY')
				""", userId, date, visibility);
	}

	private void insertDraftDiary(long userId, String date) {
		jdbc().update("""
				INSERT INTO diaries (user_id, content, content_text, written_date,
				                     analysis_status, visibility)
				VALUES (?, '{"ops":[]}'::jsonb, '초안', ?::date, 'DRAFT', 'FRIENDS')
				""", userId, date);
	}

	// ===== 권한 게이트 =====

	@Test
	void 친구면_캐릭터를_볼_수_있다() {
		long viewer = newUser("보는이");
		long target = newUser("대상");
		makeFriends(viewer, target);

		FriendCharacterResponse res = friendBrowseService.getCharacter(viewer, uuidOf(target));

		// 캐릭터 미선택 상태라 character 는 null 이지만 404 가 아니라 정상 응답이어야 한다.
		assertThat(res).isNotNull();
		assertThat(res.equipment()).isEmpty();
	}

	@Test
	void 캐릭터_조회는_대상의_상태행을_생성하지_않는다() {
		long viewer = newUser("보는이2");
		long target = newUser("대상2");
		makeFriends(viewer, target);

		friendBrowseService.getCharacter(viewer, uuidOf(target));

		// ensureState 를 타면 여기서 1이 된다(타인 계정에 JIT INSERT — 반드시 막아야 하는 회귀).
		Integer stateCount = jdbc().queryForObject(
				"SELECT COUNT(*) FROM user_character_state WHERE user_id = ?", Integer.class, target);
		Integer walletCount = jdbc().queryForObject(
				"SELECT COUNT(*) FROM user_wallets WHERE user_id = ?", Integer.class, target);
		assertThat(stateCount).isZero();
		assertThat(walletCount).isZero();
	}

	@Test
	void 친구가_아니면_404() {
		long viewer = newUser("보는이3");
		long stranger = newUser("남");

		assertThatThrownBy(() -> friendBrowseService.getCharacter(viewer, uuidOf(stranger)))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	@Test
	void 대기중인_요청만_있으면_404() {
		long viewer = newUser("보는이4");
		long target = newUser("대상4");
		friendService.sendRequest(viewer, new SendFriendRequest(null, uuidOf(target))); // PENDING 상태

		assertThatThrownBy(() -> friendBrowseService.getCharacter(viewer, uuidOf(target)))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	@Test
	void 내가_차단하면_404() {
		long viewer = newUser("보는이5");
		long target = newUser("대상5");
		makeFriends(viewer, target);
		friendService.remove(viewer, uuidOf(target), true);

		assertThatThrownBy(() -> friendBrowseService.getCharacter(viewer, uuidOf(target)))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	@Test
	void 상대가_차단하면_404() {
		long viewer = newUser("보는이6");
		long target = newUser("대상6");
		makeFriends(viewer, target);
		friendService.remove(target, uuidOf(viewer), true); // 반대 방향 차단

		assertThatThrownBy(() -> friendBrowseService.getCharacter(viewer, uuidOf(target)))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	@Test
	void 탈퇴한_사용자는_404() {
		long viewer = newUser("보는이7");
		long target = newUser("대상7");
		makeFriends(viewer, target);
		String targetUuid = uuidOf(target);
		jdbc().update("UPDATE users SET deleted_at = now() WHERE id = ?", target);

		assertThatThrownBy(() -> friendBrowseService.getCharacter(viewer, targetUuid))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	@Test
	void 없는_uuid는_404() {
		long viewer = newUser("보는이8");

		assertThatThrownBy(() ->
				friendBrowseService.getCharacter(viewer, UUID.randomUUID().toString()))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	@Test
	void 잘못된_형식의_uuid는_500이_아니라_404() {
		long viewer = newUser("보는이9");

		// ::uuid 캐스팅이 PSQLException(500)을 내지 않고 서비스가 먼저 404 로 막아야 한다.
		assertThatThrownBy(() -> friendBrowseService.getCharacter(viewer, "not-a-uuid"))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	@Test
	void 자기_자신은_404() {
		long viewer = newUser("보는이10");

		assertThatThrownBy(() -> friendBrowseService.getCharacter(viewer, uuidOf(viewer)))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	// ===== 캘린더 노출 범위 =====

	@Test
	void 캘린더는_PRIVATE와_DRAFT를_제외한다() {
		long viewer = newUser("보는이11");
		long target = newUser("대상11");
		makeFriends(viewer, target);

		insertDiary(target, "2026-03-01", "PRIVATE");
		insertDiary(target, "2026-03-02", "FRIENDS");
		insertDiary(target, "2026-03-03", "PUBLIC");
		insertDraftDiary(target, "2026-03-04");

		FriendDiarySummaryResponse res =
				friendBrowseService.getDiarySummary(viewer, uuidOf(target), "2026-03");

		assertThat(res.yearMonth()).isEqualTo("2026-03");
		assertThat(res.days()).extracting(FriendDiarySummaryDay::date)
				.containsExactly("2026-03-02", "2026-03-03"); // PRIVATE·DRAFT 는 없는 날처럼 빠진다
	}

	@Test
	void 캘린더_응답에_diaryId가_포함된다() {
		long viewer = newUser("보는이12");
		long target = newUser("대상12");
		makeFriends(viewer, target);
		insertDiary(target, "2026-04-05", "FRIENDS");

		FriendDiarySummaryResponse res =
				friendBrowseService.getDiarySummary(viewer, uuidOf(target), "2026-04");

		// 앱이 추가 왕복 없이 /feed/diary/:id 로 갈 수 있어야 한다.
		assertThat(res.days()).hasSize(1);
		assertThat(res.days().get(0).diaryId()).isNotNull();
	}

	@Test
	void 캘린더도_친구가_아니면_404() {
		long viewer = newUser("보는이13");
		long stranger = newUser("남13");
		insertDiary(stranger, "2026-05-01", "PUBLIC");

		assertThatThrownBy(() ->
				friendBrowseService.getDiarySummary(viewer, uuidOf(stranger), "2026-05"))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	// ===== 작심삼일 =====

	@Test
	void 작심삼일_목록은_친구의_것을_반환한다() {
		long viewer = newUser("보는이14");
		long target = newUser("대상14");
		makeFriends(viewer, target);
		jdbc().update("""
				INSERT INTO resolutions (user_id, title, start_date, end_date, status, streak_seq)
				VALUES (?, '매일 산책', '2026-06-01'::date, '2026-06-03'::date, 'ONGOING', 1)
				""", target);

		PageResponse<ResolutionListItem> res = friendBrowseService.getResolutions(
				viewer, uuidOf(target), null, new CursorRequest(null, null));

		assertThat(res.items()).extracting(ResolutionListItem::title).containsExactly("매일 산책");
	}

	@Test
	void 작심삼일도_친구가_아니면_404() {
		long viewer = newUser("보는이15");
		long stranger = newUser("남15");

		assertThatThrownBy(() -> friendBrowseService.getResolutions(
				viewer, uuidOf(stranger), null, new CursorRequest(null, null)))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}
}
