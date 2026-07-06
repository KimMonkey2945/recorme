package com.recordapp.domain.user.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.recordapp.domain.user.dto.UserProfileResponse;
import com.recordapp.domain.user.service.UserService;
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
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.multipart.MultipartFile;

/**
 * UserController 검증(400) 슬라이스 테스트(Docker 불필요).
 * 보안 필터 체인(SupabaseJwtFilter·SecurityConfig)은 슬라이스에서 제외하고,
 * 잘못된 바디가 GlobalExceptionHandler를 거쳐 VALIDATION_ERROR로 변환되는지 확인한다.
 * (@Valid 검증은 컨트롤러 진입 전 수행되므로 principal 없이도 400 경로를 검증할 수 있다.
 *  정상 경로·인증 principal 주입은 UserServiceTest 통합 테스트에서 검증.)
 */
@WebMvcTest(controllers = UserController.class,
		excludeFilters = @ComponentScan.Filter(
				type = FilterType.ASSIGNABLE_TYPE,
				classes = {SecurityConfig.class, SupabaseJwtFilter.class, JwtAuthenticationEntryPoint.class}),
		excludeAutoConfiguration = {SecurityAutoConfiguration.class, SecurityFilterAutoConfiguration.class})
@AutoConfigureMockMvc(addFilters = false)
class UserControllerTest {

	@Autowired
	MockMvc mockMvc;

	@MockitoBean
	UserService userService;

	private void expectValidationError(String body) throws Exception {
		mockMvc.perform(put("/users/me")
						.contentType(MediaType.APPLICATION_JSON)
						.content(body))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.success").value(false))
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(userService); // 검증 실패 시 서비스 미호출
	}

	@Test
	void update_blankNickname_returns400() throws Exception {
		expectValidationError("{\"nickname\":\"\"}");
	}

	@Test
	void update_nicknameOver50_returns400() throws Exception {
		String over = "n".repeat(51);
		expectValidationError("{\"nickname\":\"" + over + "\"}");
	}

	@Test
	void update_bioOver300_returns400() throws Exception {
		String over = "b".repeat(301);
		expectValidationError("{\"nickname\":\"valid\",\"bio\":\"" + over + "\"}");
	}

	@Test
	void uploadAvatar_valid_returns200() throws Exception {
		// 서비스(저장·검증)는 모킹 — 컨트롤러가 multipart를 받아 서비스로 위임하고 표준 응답을 내는지만 검증.
		when(userService.updateAvatar(any(), any(MultipartFile.class)))
				.thenReturn(new UserProfileResponse(
						"u-uuid", "닉", "u@e.com", "/files/avatars/2026/06/x.png", null, "ABCD1234"));
		MockMultipartFile file = new MockMultipartFile(
				"file", "a.png", MediaType.IMAGE_PNG_VALUE, new byte[] {1, 2, 3});

		mockMvc.perform(multipart("/users/me/avatar").file(file))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.profileImageUrl").value("/files/avatars/2026/06/x.png"));
	}

	@Test
	void uploadAvatar_missingFilePart_returns400() throws Exception {
		// file 파트 없는 multipart → MissingServletRequestPartException → 400 VALIDATION_ERROR(500 아님)
		mockMvc.perform(multipart("/users/me/avatar"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.success").value(false))
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(userService);
	}
}
