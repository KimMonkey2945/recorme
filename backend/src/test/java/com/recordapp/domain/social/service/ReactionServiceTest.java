package com.recordapp.domain.social.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.diary.dto.DiaryFeedItem;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.service.DiaryService;
import com.recordapp.domain.feed.service.FeedService;
import com.recordapp.domain.social.dto.ReactionResponse;
import com.recordapp.global.common.CursorRequest;
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
 * ReactionService 통합 테스트(Testcontainers PostgreSQL 18).
 * 1인 1회 멱등·취소, 볼 수 없는 글 공감 차단(404), 공감 수 캐시(diaries.reaction_count) 정합,
 * 피드/전문에 공감수·내 공감여부 반영을 검증한다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class ReactionServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	ReactionService reactionService;

	@Autowired
	FeedService feedService;

	@Autowired
	DiaryService diaryService;

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

	private String deltaOf(String text) {
		return "{\"ops\":[{\"insert\":\"" + text + "\\n\"}]}";
	}

	/** DONE 기록 1건 생성 후 id 반환(공감 대상은 DONE·볼 수 있어야 함). */
	private long doneDiary(long authorId, LocalDate date, String visibility) {
		long id = diaryService.upsert(authorId,
				new SaveDiaryRequest(deltaOf("글"), "글", date, visibility, false)).diary().id();
		jdbc().update("UPDATE diaries SET analysis_status='DONE', primary_emotion='JOY', "
				+ "mood_emoji='😊', ai_title='제목' WHERE id = ?", id);
		return id;
	}

	private int cachedCount(long diaryId) {
		return jdbc().queryForObject("SELECT reaction_count FROM diaries WHERE id = ?", Integer.class, diaryId);
	}

	// ===== 멱등 / 취소 / 캐시 정합 =====

	@Test
	void react_isIdempotent_andSyncsCache() {
		long user = newUser("r1");
		long id = doneDiary(user, LocalDate.of(2027, 1, 1), "PUBLIC");

		ReactionResponse first = reactionService.react(user, id);
		assertThat(first.reactionCount()).isEqualTo(1);
		assertThat(first.reacted()).isTrue();
		assertThat(cachedCount(id)).isEqualTo(1);

		// 중복 공감 → 여전히 1(멱등, 캐시 이중 증가 없음).
		ReactionResponse again = reactionService.react(user, id);
		assertThat(again.reactionCount()).isEqualTo(1);
		assertThat(cachedCount(id)).isEqualTo(1);
	}

	@Test
	void cancel_thenReactAgain() {
		long user = newUser("r2");
		long id = doneDiary(user, LocalDate.of(2027, 1, 2), "PUBLIC");
		reactionService.react(user, id);

		ReactionResponse cancelled = reactionService.cancel(user, id);
		assertThat(cancelled.reactionCount()).isEqualTo(0);
		assertThat(cancelled.reacted()).isFalse();
		assertThat(cachedCount(id)).isEqualTo(0);

		// 취소 후 재공감 허용.
		assertThat(reactionService.react(user, id).reactionCount()).isEqualTo(1);
	}

	@Test
	void cancel_whenNotReacted_isNoop() {
		long user = newUser("r3");
		long id = doneDiary(user, LocalDate.of(2027, 1, 3), "PUBLIC");
		ReactionResponse res = reactionService.cancel(user, id); // 원래 없음
		assertThat(res.reactionCount()).isEqualTo(0);
		assertThat(cachedCount(id)).isEqualTo(0);
	}

	// ===== 가시성 차단 =====

	@Test
	void react_invisiblePrivateOther_notFound() {
		long owner = newUser("owner");
		long stranger = newUser("stranger");
		long id = doneDiary(owner, LocalDate.of(2027, 1, 4), "PRIVATE");

		assertThatThrownBy(() -> reactionService.react(stranger, id))
				.isInstanceOf(BusinessException.class)
				.hasFieldOrPropertyWithValue("errorCode", ErrorCode.DIARY_NOT_FOUND);
		assertThat(cachedCount(id)).isEqualTo(0); // 삽입/증가 없음
	}

	// ===== 피드 반영 =====

	@Test
	void feed_reflectsReactionCountAndReactedByMe() {
		long viewer = newUser("v");
		long id = doneDiary(viewer, LocalDate.of(2027, 1, 5), "PUBLIC");
		reactionService.react(viewer, id);

		DiaryFeedItem item = feedService.getFeed(viewer, new CursorRequest(null, 50))
				.items().stream().filter(i -> i.id() == id).findFirst().orElseThrow();
		assertThat(item.reactionCount()).isEqualTo(1);
		assertThat(item.reactedByMe()).isTrue();
	}
}
