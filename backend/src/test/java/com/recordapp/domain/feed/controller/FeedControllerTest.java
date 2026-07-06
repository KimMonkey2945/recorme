package com.recordapp.domain.feed.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.recordapp.domain.diary.dto.FeedDetailResponse;
import com.recordapp.domain.feed.service.FeedService;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.security.JwtAuthenticationEntryPoint;
import com.recordapp.global.security.SecurityConfig;
import com.recordapp.global.security.SupabaseJwtFilter;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.autoconfigure.security.servlet.SecurityFilterAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.FilterType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * FeedController 슬라이스 테스트(Docker 불필요). 보안 필터 체인 제외, 위임·표준 응답만 검증.
 * 가시성 매트릭스는 FeedServiceTest(Testcontainers)에서 검증.
 */
@WebMvcTest(controllers = FeedController.class,
		excludeFilters = @ComponentScan.Filter(
				type = FilterType.ASSIGNABLE_TYPE,
				classes = {SecurityConfig.class, SupabaseJwtFilter.class, JwtAuthenticationEntryPoint.class}),
		excludeAutoConfiguration = {SecurityAutoConfiguration.class, SecurityFilterAutoConfiguration.class})
@AutoConfigureMockMvc(addFilters = false)
class FeedControllerTest {

	@Autowired
	MockMvc mockMvc;

	@MockitoBean
	FeedService feedService;

	@Test
	void feed_returns200Page() throws Exception {
		when(feedService.getFeed(any(), any()))
				.thenReturn(PageResponse.of(List.of(), null, false));

		mockMvc.perform(get("/feed"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.hasNext").value(false));
	}

	@Test
	void detail_returns200() throws Exception {
		when(feedService.getDetail(any(), eq(7L))).thenReturn(new FeedDetailResponse(
				7L, "author-uuid", "작성자", null, "{\"ops\":[]}", "본문",
				LocalDate.of(2026, 6, 15), "PUBLIC", "JOY", "#fff", "#000", "#abc",
				"코멘트", "제목", "😊", 0, false));

		mockMvc.perform(get("/feed/7"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.authorNickname").value("작성자"))
				.andExpect(jsonPath("$.data.id").value(7));

		verify(feedService).getDetail(any(), eq(7L));
	}
}
