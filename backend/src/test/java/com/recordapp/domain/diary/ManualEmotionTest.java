package com.recordapp.domain.diary;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.diary.dto.DiaryResponse;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.service.DiaryService;
import com.recordapp.domain.emotion.service.EmotionAnalysisPoller;
import com.recordapp.domain.emotion.service.EmotionAnalysisService;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import com.recordapp.infra.llm.LlmClient;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.NoSuchBeanDefinitionException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.ApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 감정 사용자 직접 입력(Task 024) 통합 테스트 — 분석 flag <b>off</b> 컨텍스트.
 *
 * <p>{@code record.analysis.enabled=false} 로 고정해(운영 기본값), 확정 시 즉시 DONE 전이 + 사용자 감정 저장,
 * 프리셋/자유텍스트 상호 배타, 감정 미입력 확정 허용(V19 CHECK 해제), 최근 라벨 추천, 그리고
 * 감정/LLM 빈이 <b>미등록</b>됨을 검증한다. on 경로 회귀는 {@link EmotionAnalysisEnabledTest} 가 담당한다.
 *
 * <p>⚠️ {@code @Transactional} 을 두지 않는다(DiaryServiceTest 와 동일 — afterCommit 동기화 검증 위함).
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
@TestPropertySource(properties = "record.analysis.enabled=false")
class ManualEmotionTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	DiaryService diaryService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	@Autowired
	ApplicationContext context;

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	private long newUser() {
		String sub = UUID.randomUUID().toString();
		return provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", "tester"), Map.of("sub", sub)))
				.userId();
	}

	private String deltaOf(String text) {
		return "{\"ops\":[{\"insert\":\"" + text + "\\n\"}]}";
	}

	/** 감정을 실은 확정(confirm=true) 요청. emotion/emotionLabel 중 하나 또는 둘 다 null 가능. */
	private SaveDiaryRequest confirmWithEmotion(String text, LocalDate date, String emotion, String emotionLabel) {
		return new SaveDiaryRequest(deltaOf(text), text, date, "PRIVATE", true, emotion, emotionLabel);
	}

	private String emotionLabelOf(long diaryId) {
		return jdbc().queryForObject("SELECT emotion_label FROM diaries WHERE id = ?", String.class, diaryId);
	}

	// ===== off: 확정 시 즉시 DONE + 사용자 감정 저장 =====

	@Test
	void confirmWithPreset_immediatelyDone_savesPrimaryEmotion_noAiFields() {
		long userId = newUser();
		DiaryUpsertResult r = diaryService.upsert(userId,
				confirmWithEmotion("기쁜 하루", LocalDate.of(2026, 4, 1), "JOY", null));

		DiaryResponse d = r.diary();
		// 분석 대기 없이 즉시 확정
		assertThat(d.analysisStatus()).isEqualTo("DONE");
		// 사용자 프리셋 감정 저장, 자유 텍스트는 없음
		assertThat(d.primaryEmotion()).isEqualTo("JOY");
		assertThat(emotionLabelOf(d.id())).isNull();
		// LLM 산출(색·코멘트·제목·이모지)은 전부 NULL — 분석을 돌리지 않았다
		assertThat(d.backgroundColor()).isNull();
		assertThat(d.textColor()).isNull();
		assertThat(d.accentColor()).isNull();
		assertThat(d.aiComment()).isNull();
		assertThat(d.aiTitle()).isNull();
		assertThat(d.moodEmoji()).isNull();
	}

	@Test
	void confirmWithCustomLabel_immediatelyDone_savesLabel_noPreset() {
		long userId = newUser();
		DiaryUpsertResult r = diaryService.upsert(userId,
				confirmWithEmotion("두근두근", LocalDate.of(2026, 4, 2), null, "설렘"));

		assertThat(r.diary().analysisStatus()).isEqualTo("DONE");
		assertThat(r.diary().primaryEmotion()).isNull();
		assertThat(emotionLabelOf(r.diary().id())).isEqualTo("설렘");
	}

	@Test
	void confirmWithoutEmotion_immediatelyDone_checkReleased() {
		long userId = newUser();
		// 감정 미입력 확정 — V19 에서 chk_diaries_done_has_emotion 을 드롭했으므로 DONE 이어도 감정 NULL 허용.
		DiaryUpsertResult r = diaryService.upsert(userId,
				confirmWithEmotion("무던한 하루", LocalDate.of(2026, 4, 3), null, null));

		assertThat(r.diary().analysisStatus()).isEqualTo("DONE");
		assertThat(r.diary().primaryEmotion()).isNull();
		assertThat(emotionLabelOf(r.diary().id())).isNull();
	}

	@Test
	void customLabel_boundary20chars_persists() {
		long userId = newUser();
		String label20 = "가".repeat(20); // 경계값(정확히 20자)
		DiaryUpsertResult r = diaryService.upsert(userId,
				confirmWithEmotion("경계", LocalDate.of(2026, 4, 4), null, label20));

		assertThat(emotionLabelOf(r.diary().id())).isEqualTo(label20);
	}

	// ===== off: 검증/에러 =====

	@Test
	void presetAndCustom_together_throwsConflict() {
		long userId = newUser();
		assertThatThrownBy(() -> diaryService.upsert(userId,
				confirmWithEmotion("둘 다", LocalDate.of(2026, 4, 5), "JOY", "설렘")))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.EMOTION_CONFLICT));
	}

	@Test
	void unknownPresetCode_throwsValidationError() {
		long userId = newUser();
		assertThatThrownBy(() -> diaryService.upsert(userId,
				confirmWithEmotion("이상한 코드", LocalDate.of(2026, 4, 6), "HAPPINESS", null)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.VALIDATION_ERROR));
	}

	// ===== off: 최근 커스텀 감정 라벨 추천 =====

	@Test
	void recentEmotionLabels_dedupedAndMostRecentFirst() {
		long userId = newUser();
		diaryService.upsert(userId, confirmWithEmotion("A", LocalDate.of(2026, 5, 1), null, "행복"));
		diaryService.upsert(userId, confirmWithEmotion("B", LocalDate.of(2026, 5, 2), null, "설렘"));
		diaryService.upsert(userId, confirmWithEmotion("C", LocalDate.of(2026, 5, 3), null, "행복")); // 행복 재사용(더 최근)

		List<String> recent = diaryService.getRecentEmotionLabels(userId);
		// 라벨 단위 중복 제거 + 최근 사용순 → [행복(5/3), 설렘(5/2)]
		assertThat(recent).containsExactly("행복", "설렘");
	}

	// ===== off: 감정/LLM 빈 미등록 =====

	@Test
	void analysisBeans_notRegistered_whenFlagOff() {
		assertThatThrownBy(() -> context.getBean(EmotionAnalysisService.class))
				.isInstanceOf(NoSuchBeanDefinitionException.class);
		assertThatThrownBy(() -> context.getBean(EmotionAnalysisPoller.class))
				.isInstanceOf(NoSuchBeanDefinitionException.class);
		assertThatThrownBy(() -> context.getBean(LlmClient.class))
				.isInstanceOf(NoSuchBeanDefinitionException.class);
	}
}
