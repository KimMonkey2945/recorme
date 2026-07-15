package com.recordapp.domain.diary.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.recordapp.domain.diary.dto.DiaryResponse;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.dto.SharedDiaryResponse;
import com.recordapp.domain.diary.dto.UpdateVisibilityRequest;
import com.recordapp.domain.diary.service.DiaryService;
import com.recordapp.global.security.JwtAuthenticationEntryPoint;
import com.recordapp.global.security.SecurityConfig;
import com.recordapp.global.security.SupabaseJwtFilter;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.autoconfigure.security.servlet.SecurityFilterAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.FilterType;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * DiaryController 검증(400) 슬라이스 테스트(Docker 불필요).
 * 보안 필터 체인(SupabaseJwtFilter·SecurityConfig)은 슬라이스에서 제외하고,
 * 잘못된 바디·누락 파트가 GlobalExceptionHandler를 거쳐 VALIDATION_ERROR로 변환되는지 확인한다.
 * (@Valid 검증은 컨트롤러 진입 전 수행되므로 principal 없이도 400 경로를 검증할 수 있다.
 *  정상 경로·인증 principal 주입·소유권은 DiaryServiceTest 통합 테스트에서 검증.)
 */
@WebMvcTest(controllers = DiaryController.class,
		excludeFilters = @ComponentScan.Filter(
				type = FilterType.ASSIGNABLE_TYPE,
				classes = {SecurityConfig.class, SupabaseJwtFilter.class, JwtAuthenticationEntryPoint.class}),
		excludeAutoConfiguration = {SecurityAutoConfiguration.class, SecurityFilterAutoConfiguration.class})
@AutoConfigureMockMvc(addFilters = false)
class DiaryControllerTest {

	@Autowired
	MockMvc mockMvc;

	@MockitoBean
	DiaryService diaryService;

	private void expectSaveValidationError(String body) throws Exception {
		mockMvc.perform(post("/diaries")
						.contentType(MediaType.APPLICATION_JSON)
						.content(body))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.success").value(false))
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(diaryService); // 검증 실패 시 서비스 미호출
	}

	@Test
	void save_blankContent_returns400() throws Exception {
		// content(Delta JSON, @NotBlank) 공백 → 400. contentText 는 정상값을 줘 content 누락만 검증.
		expectSaveValidationError("{\"content\":\"\",\"contentText\":\"ok\",\"writtenDate\":\"2026-06-15\"}");
	}

	@Test
	void save_contentTextOver500_returns400() throws Exception {
		// 길이 제약은 순수 텍스트(contentText, @Size)에만 둔다. content(Delta JSON)는 길이 무제한.
		String over = "a".repeat(501);
		expectSaveValidationError(
				"{\"content\":\"delta\",\"contentText\":\"" + over + "\",\"writtenDate\":\"2026-06-15\"}");
	}

	@Test
	void save_blankContentText_returns400() throws Exception {
		// contentText(@NotBlank) 공백 → 400.
		expectSaveValidationError("{\"content\":\"delta\",\"contentText\":\"\",\"writtenDate\":\"2026-06-15\"}");
	}

	@Test
	void save_missingWrittenDate_returns400() throws Exception {
		// writtenDate(@NotNull) 누락 → 400
		expectSaveValidationError("{\"content\":\"delta\",\"contentText\":\"ok\"}");
	}

	@Test
	void uploadImage_missingFilePart_returns400() throws Exception {
		// file 파트 없는 multipart → MissingServletRequestPartException → 400 VALIDATION_ERROR(500 아님)
		mockMvc.perform(multipart("/diaries/images"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.success").value(false))
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(diaryService);
	}

	@Test
	void save_valid_returns201() throws Exception {
		// 서비스는 모킹 — 컨트롤러가 inserted=true 결과를 201 + 표준 응답으로 내는지만 검증.
		// content 는 Delta JSON, contentText 는 순수 텍스트.
		DiaryResponse diary = new DiaryResponse(
				10L, "share-token", "{\"ops\":[{\"insert\":\"오늘 하루\\n\"}]}", "오늘 하루",
				LocalDate.of(2026, 6, 15), "PRIVATE", "PENDING",
				null, null, null, null, null, null, null, null); // 감정 분석 테마 필드(미분석 → NULL)
		when(diaryService.upsert(any(), any(SaveDiaryRequest.class)))
				.thenReturn(new DiaryUpsertResult(diary, true));

		mockMvc.perform(post("/diaries")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"content\":\"delta\",\"contentText\":\"오늘 하루\",\"writtenDate\":\"2026-06-15\"}"))
				.andExpect(status().isCreated())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.id").value(10))
				.andExpect(jsonPath("$.data.contentText").value("오늘 하루"))
				.andExpect(jsonPath("$.data.analysisStatus").value("PENDING"));
	}

	@Test
	void save_confirmFlag_boundToRequest() throws Exception {
		// 바디의 confirm=true 가 SaveDiaryRequest.confirm 으로 역직렬화돼 서비스에 전달되는지 검증.
		DiaryResponse diary = new DiaryResponse(
				11L, "share-token", "{\"ops\":[{\"insert\":\"확정\\n\"}]}", "확정",
				LocalDate.of(2026, 6, 16), "PRIVATE", "PENDING",
				null, null, null, null, null, null, null, null); // 감정 분석 테마 필드(미분석 → NULL)
		when(diaryService.upsert(any(), any(SaveDiaryRequest.class)))
				.thenReturn(new DiaryUpsertResult(diary, true));

		mockMvc.perform(post("/diaries")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"content\":\"delta\",\"contentText\":\"확정\",\"writtenDate\":\"2026-06-16\",\"confirm\":true}"))
				.andExpect(status().isCreated());

		ArgumentCaptor<SaveDiaryRequest> captor = ArgumentCaptor.forClass(SaveDiaryRequest.class);
		verify(diaryService).upsert(any(), captor.capture());
		assertThat(captor.getValue().confirm()).as("confirm=true 바인딩").isEqualTo(true);
	}

	@Test
	void save_confirmOmitted_boundAsNull() throws Exception {
		// confirm 미지정 시 null 로 바인딩(서비스에서 등록=DRAFT 로 해석). 컨트롤러는 그대로 전달만 한다.
		DiaryResponse diary = new DiaryResponse(
				12L, "share-token", "{\"ops\":[{\"insert\":\"등록\\n\"}]}", "등록",
				LocalDate.of(2026, 6, 17), "PRIVATE", "DRAFT",
				null, null, null, null, null, null, null, null); // 감정 분석 테마 필드(미분석 → NULL)
		when(diaryService.upsert(any(), any(SaveDiaryRequest.class)))
				.thenReturn(new DiaryUpsertResult(diary, true));

		mockMvc.perform(post("/diaries")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"content\":\"delta\",\"contentText\":\"등록\",\"writtenDate\":\"2026-06-17\"}"))
				.andExpect(status().isCreated())
				.andExpect(jsonPath("$.data.analysisStatus").value("DRAFT"));

		ArgumentCaptor<SaveDiaryRequest> captor = ArgumentCaptor.forClass(SaveDiaryRequest.class);
		verify(diaryService).upsert(any(), captor.capture());
		assertThat(captor.getValue().confirm()).as("confirm 미지정 → null").isNull();
	}

	@Test
	void changeVisibility_valid_returns200() throws Exception {
		// 서비스는 모킹 — 컨트롤러가 PATCH 바디를 받아 위임하고 표준 응답을 내는지만 검증.
		DiaryResponse diary = new DiaryResponse(
				10L, "share-token", "{\"ops\":[]}", "본문",
				LocalDate.of(2026, 6, 15), "FRIENDS", "DONE",
				null, null, null, null, null, null, null, null);
		when(diaryService.changeVisibility(any(), any(), any(UpdateVisibilityRequest.class)))
				.thenReturn(diary);

		mockMvc.perform(patch("/diaries/10/visibility")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"visibility\":\"FRIENDS\"}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.visibility").value("FRIENDS"));
	}

	@Test
	void changeVisibility_blank_returns400() throws Exception {
		// visibility(@NotBlank) 공백 → 400 VALIDATION_ERROR, 서비스 미호출.
		mockMvc.perform(patch("/diaries/10/visibility")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"visibility\":\"\"}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(diaryService);
	}

	@Test
	void getShared_returns200() throws Exception {
		// 공유 링크 공개 조회 — 작성자 표시명·본문·테마만 담긴 응답 위임.
		when(diaryService.getShared(any())).thenReturn(new SharedDiaryResponse(
				"작성자", null, "{\"ops\":[]}", "본문",
				LocalDate.of(2026, 6, 15), "JOY", "#fff", "#000", "#abc", "코멘트", "제목", "😊"));

		mockMvc.perform(get("/diaries/shared/some-token"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.authorNickname").value("작성자"))
				.andExpect(jsonPath("$.data.moodEmoji").value("😊"));
	}
}
