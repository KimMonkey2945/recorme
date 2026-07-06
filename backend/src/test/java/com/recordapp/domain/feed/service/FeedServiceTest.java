package com.recordapp.domain.feed.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.diary.dto.DiaryFeedItem;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.service.DiaryService;
import com.recordapp.domain.social.dto.SendFriendRequest;
import com.recordapp.domain.social.service.FriendService;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import java.time.LocalDate;
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
 * FeedService 통합 테스트(Testcontainers PostgreSQL 18).
 * 가시성 매트릭스(본인·PUBLIC·수락친구 FRIENDS 노출 / PRIVATE·비친구 FRIENDS·차단·DRAFT 미노출),
 * 커서 페이징, viewer-aware 전문 조회(볼 수 없으면 404)를 검증한다.
 *
 * <p>감정 분석(async)은 비결정적이라, 확정 대신 DRAFT 저장 후 JdbcTemplate 로 DONE+감정을 직접 세팅해
 * 피드 노출 조건(analysis_status='DONE')을 결정적으로 만든다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class FeedServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	FeedService feedService;

	@Autowired
	DiaryService diaryService;

	@Autowired
	FriendService friendService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

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

	private String friendCodeOf(long userId) {
		return jdbc().queryForObject("SELECT friend_code FROM users WHERE id = ?", String.class, userId);
	}

	/** 두 사용자를 수락된 친구로 만든다. */
	private void makeFriends(long a, long b) {
		var res = friendService.sendRequest(a, new SendFriendRequest(friendCodeOf(b), null));
		friendService.accept(b, res.requestId());
	}

	private String deltaOf(String text) {
		return "{\"ops\":[{\"insert\":\"" + text + "\\n\"}]}";
	}

	/** DONE(감정 세팅) 기록 1건 생성 후 id 반환. 피드 노출 조건을 결정적으로 만든다. */
	private long doneDiary(long authorId, LocalDate date, String visibility) {
		var saved = diaryService.upsert(authorId,
				new SaveDiaryRequest(deltaOf("글"), "글", date, visibility, false));
		long id = saved.diary().id();
		jdbc().update("UPDATE diaries SET analysis_status='DONE', primary_emotion='JOY', "
				+ "mood_emoji='😊', ai_title='제목' WHERE id = ?", id);
		return id;
	}

	/** DRAFT(미확정) 기록 1건 생성 후 id 반환. */
	private long draftDiary(long authorId, LocalDate date, String visibility) {
		return diaryService.upsert(authorId,
				new SaveDiaryRequest(deltaOf("초안"), "초안", date, visibility, false)).diary().id();
	}

	private List<String> feedAuthorUuids(long viewerId) {
		return feedService.getFeed(viewerId, new CursorRequest(null, 50))
				.items().stream().map(DiaryFeedItem::authorUuid).toList();
	}

	// ===== 가시성 매트릭스 =====

	@Test
	void feed_includesOwn_publicOfAnyone_friendsOfFriend() {
		long viewer = newUser("viewer");
		long friend = newUser("friend");
		long stranger = newUser("stranger");
		makeFriends(viewer, friend);

		doneDiary(viewer, LocalDate.of(2026, 11, 1), "PRIVATE");   // 본인 → 보임(상태 DONE)
		doneDiary(friend, LocalDate.of(2026, 11, 2), "FRIENDS");   // 친구 FRIENDS → 보임
		doneDiary(friend, LocalDate.of(2026, 11, 3), "PUBLIC");    // 친구 PUBLIC → 보임
		doneDiary(stranger, LocalDate.of(2026, 11, 4), "PUBLIC");  // 낯선 사람 PUBLIC → 보임

		List<String> authors = feedAuthorUuids(viewer);
		assertThat(authors).contains(uuidOf(viewer), uuidOf(friend), uuidOf(stranger));
	}

	@Test
	void feed_excludes_privateOthers_nonFriendFriends_draft() {
		long viewer = newUser("v2");
		long friend = newUser("f2");
		long stranger = newUser("s2");
		makeFriends(viewer, friend);

		doneDiary(stranger, LocalDate.of(2026, 11, 5), "PRIVATE");  // 타인 PRIVATE → 미노출
		doneDiary(stranger, LocalDate.of(2026, 11, 6), "FRIENDS");  // 비친구 FRIENDS → 미노출
		draftDiary(friend, LocalDate.of(2026, 11, 7), "PUBLIC");    // 친구 DRAFT → 미노출(DONE 아님)

		assertThat(feedAuthorUuids(viewer)).doesNotContain(uuidOf(stranger));
		// 친구의 DRAFT 는 노출 안 됨 → 친구 글이 하나도 없으므로 friend uuid 미포함.
		assertThat(feedAuthorUuids(viewer)).doesNotContain(uuidOf(friend));
	}

	@Test
	void feed_excludesBlocked_evenPublic() {
		long viewer = newUser("v3");
		long blocked = newUser("b3");
		doneDiary(blocked, LocalDate.of(2026, 11, 8), "PUBLIC");
		friendService.remove(viewer, uuidOf(blocked), true); // viewer 가 blocked 차단

		assertThat(feedAuthorUuids(viewer)).doesNotContain(uuidOf(blocked));
	}

	@Test
	void feed_cursorPaging_limitsPageSize() {
		long viewer = newUser("v4");
		for (int i = 0; i < 3; i++) {
			doneDiary(viewer, LocalDate.of(2026, 12, 1).plusDays(i), "PRIVATE");
		}
		var page = feedService.getFeed(viewer, new CursorRequest(null, 2));
		assertThat(page.items()).hasSize(2);
		assertThat(page.hasNext()).isTrue();
		assertThat(page.nextCursor()).isNotNull();
	}

	// ===== viewer-aware 전문 조회 =====

	@Test
	void getDetail_friendRecord_returnsWithAuthor() {
		long viewer = newUser("v5");
		long friend = newUser("f5");
		makeFriends(viewer, friend);
		long id = doneDiary(friend, LocalDate.of(2026, 11, 10), "FRIENDS");

		var detail = feedService.getDetail(viewer, id);
		assertThat(detail.contentText()).isEqualTo("글");
		assertThat(detail.authorNickname()).isNotBlank();
	}

	@Test
	void getDetail_privateOther_notFound() {
		long viewer = newUser("v6");
		long stranger = newUser("s6");
		long id = doneDiary(stranger, LocalDate.of(2026, 11, 11), "PRIVATE");

		assertThatThrownBy(() -> feedService.getDetail(viewer, id))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.DIARY_NOT_FOUND);
	}
}
