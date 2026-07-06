package com.recordapp.domain.social.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.recordapp.domain.social.dto.ReactionResponse;
import com.recordapp.domain.social.service.ReactionService;
import com.recordapp.global.security.JwtAuthenticationEntryPoint;
import com.recordapp.global.security.SecurityConfig;
import com.recordapp.global.security.SupabaseJwtFilter;
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
 * ReactionController 슬라이스 테스트(Docker 불필요). 위임·표준 응답만 검증.
 * 멱등·가시성·카운트 정합은 ReactionServiceTest(Testcontainers)에서 검증.
 */
@WebMvcTest(controllers = ReactionController.class,
		excludeFilters = @ComponentScan.Filter(
				type = FilterType.ASSIGNABLE_TYPE,
				classes = {SecurityConfig.class, SupabaseJwtFilter.class, JwtAuthenticationEntryPoint.class}),
		excludeAutoConfiguration = {SecurityAutoConfiguration.class, SecurityFilterAutoConfiguration.class})
@AutoConfigureMockMvc(addFilters = false)
class ReactionControllerTest {

	@Autowired
	MockMvc mockMvc;

	@MockitoBean
	ReactionService reactionService;

	@Test
	void add_returns200WithCount() throws Exception {
		when(reactionService.react(any(), eq(5L))).thenReturn(new ReactionResponse(1, true));

		mockMvc.perform(post("/diaries/5/reactions"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.reactionCount").value(1))
				.andExpect(jsonPath("$.data.reacted").value(true));
		verify(reactionService).react(any(), eq(5L));
	}

	@Test
	void remove_returns200() throws Exception {
		when(reactionService.cancel(any(), eq(5L))).thenReturn(new ReactionResponse(0, false));

		mockMvc.perform(delete("/diaries/5/reactions"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.reactionCount").value(0))
				.andExpect(jsonPath("$.data.reacted").value(false));
		verify(reactionService).cancel(any(), eq(5L));
	}
}
