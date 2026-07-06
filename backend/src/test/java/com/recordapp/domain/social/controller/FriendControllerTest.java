package com.recordapp.domain.social.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.recordapp.domain.social.dto.FriendRequestResponse;
import com.recordapp.domain.social.service.FriendService;
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
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * FriendController 슬라이스 테스트(Docker 불필요). 보안 필터 체인은 제외하고,
 * 컨트롤러가 서비스로 위임하고 표준 응답/상태코드를 내는지만 검증한다.
 * 정상 경로·상태 전이·소유권 가드는 FriendServiceTest(Testcontainers)에서 검증.
 */
@WebMvcTest(controllers = FriendController.class,
		excludeFilters = @ComponentScan.Filter(
				type = FilterType.ASSIGNABLE_TYPE,
				classes = {SecurityConfig.class, SupabaseJwtFilter.class, JwtAuthenticationEntryPoint.class}),
		excludeAutoConfiguration = {SecurityAutoConfiguration.class, SecurityFilterAutoConfiguration.class})
@AutoConfigureMockMvc(addFilters = false)
class FriendControllerTest {

	@Autowired
	MockMvc mockMvc;

	@MockitoBean
	FriendService friendService;

	@Test
	void request_returns201() throws Exception {
		when(friendService.sendRequest(any(), any()))
				.thenReturn(new FriendRequestResponse(10L, "PENDING"));

		mockMvc.perform(post("/friends/requests")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"friendCode\":\"ABCD1234\"}"))
				.andExpect(status().isCreated())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.requestId").value(10))
				.andExpect(jsonPath("$.data.status").value("PENDING"));
	}

	@Test
	void remove_defaultsToUnfriend_returns200() throws Exception {
		mockMvc.perform(delete("/friends/{uuid}", "target-uuid"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true));

		verify(friendService).remove(any(), eq("target-uuid"), eq(false)); // block 기본 false
	}

	@Test
	void block_passesFlag_returns200() throws Exception {
		mockMvc.perform(delete("/friends/{uuid}", "target-uuid").param("block", "true"))
				.andExpect(status().isOk());

		verify(friendService).remove(any(), eq("target-uuid"), eq(true));
	}

	@Test
	void accept_returns200() throws Exception {
		mockMvc.perform(post("/friends/requests/{id}/accept", 5))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true));

		verify(friendService).accept(any(), eq(5L));
	}
}
