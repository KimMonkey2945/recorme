package com.recordapp.domain.diary;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.service.DiaryService;
import com.recordapp.domain.emotion.service.EmotionAnalysisPoller;
import com.recordapp.domain.emotion.service.EmotionAnalysisService;
import com.recordapp.global.security.SupabaseClaims;
import com.recordapp.infra.llm.LlmClient;
import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 감정 분석 flag <b>on</b> 회귀 테스트(Task 024) — 기존 LLM 분석 경로 무손상 확인.
 *
 * <p>{@code record.analysis.enabled=true} 컨텍스트에서 확정 시 즉시 DONE 이 아니라 <b>PENDING</b> 으로
 * 전이하고(커밋 후 비동기 분석 대기), 감정/LLM 빈이 <b>등록</b>돼 있음을 검증한다.
 * (비동기 분석 완료→DONE 은 타이밍 비결정성이 있어 여기서 대기하지 않는다 — 상태 전이·빈 등록까지만 확인.)
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
@TestPropertySource(properties = "record.analysis.enabled=true")
class EmotionAnalysisEnabledTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	DiaryService diaryService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	ApplicationContext context;

	private long newUser() {
		String sub = UUID.randomUUID().toString();
		return provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", "tester"), Map.of("sub", sub)))
				.userId();
	}

	private String deltaOf(String text) {
		return "{\"ops\":[{\"insert\":\"" + text + "\\n\"}]}";
	}

	@Test
	void confirm_setsPending_whenFlagOn() {
		long userId = newUser();
		DiaryUpsertResult r = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("오늘을 기억"), "오늘을 기억", LocalDate.of(2026, 6, 1), "PRIVATE", true));

		// 분석 on 이면 확정 시 즉시 DONE 이 아니라 PENDING(커밋 후 비동기 분석 대기).
		assertThat(r.diary().analysisStatus()).isEqualTo("PENDING");
	}

	@Test
	void analysisBeans_registered_whenFlagOn() {
		assertThatCode(() -> {
			context.getBean(EmotionAnalysisService.class);
			context.getBean(EmotionAnalysisPoller.class);
			context.getBean(LlmClient.class);
		}).doesNotThrowAnyException();
	}
}
