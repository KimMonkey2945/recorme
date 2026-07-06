package com.recordapp.domain.social.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.social.dto.FriendItem;
import com.recordapp.domain.social.dto.FriendRequestResponse;
import com.recordapp.domain.social.dto.FriendSearchItem;
import com.recordapp.domain.social.dto.SendFriendRequest;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import java.util.List;
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
 * FriendService 통합 테스트(Testcontainers PostgreSQL 18).
 * 친구코드 발급·유일성, 친구코드/닉네임 검색, 요청→수락/거절, 역방향 자동수락,
 * 중복·자기요청·이미친구 차단, 삭제·차단(재요청 차단), 양방향 중복 미생성을 검증한다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class FriendServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

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

	/** JIT로 회원 1명 생성(고유 sub·nickname) 후 내부 PK 반환. */
	private long newUser(String nickname) {
		String sub = UUID.randomUUID().toString();
		return provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", nickname),
						Map.of("sub", sub))).userId();
	}

	private String friendCodeOf(long userId) {
		return jdbc().queryForObject("SELECT friend_code FROM users WHERE id = ?", String.class, userId);
	}

	private String uuidOf(long userId) {
		return jdbc().queryForObject("SELECT uuid::text FROM users WHERE id = ?", String.class, userId);
	}

	private SendFriendRequest byCode(String code) {
		return new SendFriendRequest(code, null);
	}

	private SendFriendRequest byUuid(String uuid) {
		return new SendFriendRequest(null, uuid);
	}

	// ===== 친구코드 =====

	@Test
	void provision_assignsUniqueFriendCode() {
		long a = newUser("alice");
		long b = newUser("bob");
		String codeA = friendCodeOf(a);
		String codeB = friendCodeOf(b);

		assertThat(codeA).hasSize(8).matches("[0-9A-HJKMNP-TV-Z]{8}"); // 혼동문자(I,L,O,U) 제외
		assertThat(codeA).isNotEqualTo(codeB);
	}

	// ===== 요청 / 수락 =====

	@Test
	void sendRequestByCode_thenAccept_makesFriends() {
		long a = newUser("req-a");
		long b = newUser("req-b");

		FriendRequestResponse res = friendService.sendRequest(a, byCode(friendCodeOf(b)));
		assertThat(res.status()).isEqualTo("PENDING");

		friendService.accept(b, res.requestId());

		// 양쪽 목록 모두에서 상대가 보인다.
		assertThat(friendService.getFriends(a, new CursorRequest(null, 20)).items())
				.extracting(FriendItem::userUuid).contains(uuidOf(b));
		assertThat(friendService.getFriends(b, new CursorRequest(null, 20)).items())
				.extracting(FriendItem::userUuid).contains(uuidOf(a));
	}

	@Test
	void sendRequestByUuid_works() {
		long a = newUser("uuid-a");
		long b = newUser("uuid-b");
		FriendRequestResponse res = friendService.sendRequest(a, byUuid(uuidOf(b)));
		assertThat(res.status()).isEqualTo("PENDING");
	}

	@Test
	void reverseRequest_autoAccepts() {
		long a = newUser("rev-a");
		long b = newUser("rev-b");
		friendService.sendRequest(a, byCode(friendCodeOf(b)));

		// B가 A에게 다시 요청 → 자동 수락(상호 요청 = 친구 성립).
		FriendRequestResponse res = friendService.sendRequest(b, byCode(friendCodeOf(a)));
		assertThat(res.status()).isEqualTo("ACCEPTED");
		assertThat(friendService.getFriends(a, new CursorRequest(null, 20)).items()).hasSize(1);
	}

	@Test
	void duplicateSameDirection_throws() {
		long a = newUser("dup-a");
		long b = newUser("dup-b");
		friendService.sendRequest(a, byCode(friendCodeOf(b)));

		assertThatThrownBy(() -> friendService.sendRequest(a, byCode(friendCodeOf(b))))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.FRIEND_REQUEST_ALREADY_SENT);
	}

	@Test
	void alreadyFriends_throws() {
		long a = newUser("af-a");
		long b = newUser("af-b");
		FriendRequestResponse res = friendService.sendRequest(a, byCode(friendCodeOf(b)));
		friendService.accept(b, res.requestId());

		assertThatThrownBy(() -> friendService.sendRequest(a, byCode(friendCodeOf(b))))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.FRIEND_ALREADY);
	}

	@Test
	void selfRequest_throws() {
		long a = newUser("self-a");
		assertThatThrownBy(() -> friendService.sendRequest(a, byCode(friendCodeOf(a))))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.FRIEND_SELF);
	}

	@Test
	void unknownTarget_throwsUserNotFound() {
		long a = newUser("unk-a");
		assertThatThrownBy(() -> friendService.sendRequest(a, byCode("ZZZZ9999")))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
	}

	// ===== 거절 =====

	@Test
	void reject_removesRequest() {
		long a = newUser("rej-a");
		long b = newUser("rej-b");
		FriendRequestResponse res = friendService.sendRequest(a, byCode(friendCodeOf(b)));

		friendService.reject(b, res.requestId());
		assertThat(friendService.getRequests(b, "incoming", new CursorRequest(null, 20)).items()).isEmpty();
	}

	@Test
	void accept_byNonAddressee_throwsNotFound() {
		long a = newUser("na-a");
		long b = newUser("na-b");
		FriendRequestResponse res = friendService.sendRequest(a, byCode(friendCodeOf(b)));

		// 요청자(A)가 자기 요청을 수락하려 하면 수신자 가드로 404.
		assertThatThrownBy(() -> friendService.accept(a, res.requestId()))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.FRIEND_REQUEST_NOT_FOUND);
	}

	// ===== 검색 =====

	@Test
	void search_byNicknameAndCode_excludesSelf_withRelation() {
		long me = newUser("searcher");
		long other = newUser("findme-target");

		// 닉네임 부분일치
		List<FriendSearchItem> byNick = friendService.search(me, "findme");
		assertThat(byNick).extracting(FriendSearchItem::userUuid).contains(uuidOf(other));
		assertThat(byNick).extracting(FriendSearchItem::userUuid).doesNotContain(uuidOf(me));
		assertThat(byNick).allSatisfy(i -> assertThat(i.relation()).isEqualTo("NONE"));

		// 요청 후 relation 라벨 갱신
		friendService.sendRequest(me, byUuid(uuidOf(other)));
		List<FriendSearchItem> byCode = friendService.search(me, friendCodeOf(other));
		assertThat(byCode).hasSize(1);
		assertThat(byCode.get(0).relation()).isEqualTo("REQUESTED");
	}

	// ===== 삭제 / 차단 =====

	@Test
	void unfriend_removesRelation() {
		long a = newUser("uf-a");
		long b = newUser("uf-b");
		FriendRequestResponse res = friendService.sendRequest(a, byCode(friendCodeOf(b)));
		friendService.accept(b, res.requestId());

		friendService.remove(a, uuidOf(b), false);
		assertThat(friendService.getFriends(a, new CursorRequest(null, 20)).items()).isEmpty();
	}

	@Test
	void block_preventsReRequest() {
		long a = newUser("bl-a");
		long b = newUser("bl-b");
		friendService.remove(a, uuidOf(b), true); // A가 B 차단

		// 어느 쪽이 요청해도 BLOCKED.
		assertThatThrownBy(() -> friendService.sendRequest(b, byCode(friendCodeOf(a))))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.FRIEND_BLOCKED);
		assertThatThrownBy(() -> friendService.sendRequest(a, byCode(friendCodeOf(b))))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.FRIEND_BLOCKED);
	}

	@Test
	void pairRow_isUniqueRegardlessOfDirection() {
		long a = newUser("uniq-a");
		long b = newUser("uniq-b");
		friendService.sendRequest(a, byCode(friendCodeOf(b))); // A→B PENDING
		friendService.sendRequest(b, byCode(friendCodeOf(a))); // B→A → 자동수락(같은 행)

		Integer rows = jdbc().queryForObject(
				"SELECT count(*) FROM friendships WHERE LEAST(requester_id,addressee_id)=? "
						+ "AND GREATEST(requester_id,addressee_id)=?",
				Integer.class, Math.min(a, b), Math.max(a, b));
		assertThat(rows).isEqualTo(1); // 무방향 쌍당 1행
	}
}
