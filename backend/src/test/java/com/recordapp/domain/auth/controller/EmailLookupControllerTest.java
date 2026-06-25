package com.recordapp.domain.auth.controller;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.recordapp.domain.auth.service.EmailLookupService;
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
 * EmailLookupController 슬라이스 테스트(Docker 불필요).
 * 보안 필터 체인을 제외하고, 컨트롤러가 서비스 결과를 표준 응답으로 내는지만 검증한다.
 * (실제 permitAll 허용은 SecurityConfig 통합 경로에서 보장된다.)
 */
@WebMvcTest(controllers = EmailLookupController.class,
		excludeFilters = @ComponentScan.Filter(
				type = FilterType.ASSIGNABLE_TYPE,
				classes = {SecurityConfig.class, SupabaseJwtFilter.class, JwtAuthenticationEntryPoint.class}),
		excludeAutoConfiguration = {SecurityAutoConfiguration.class, SecurityFilterAutoConfiguration.class})
@AutoConfigureMockMvc(addFilters = false)
class EmailLookupControllerTest {

	@Autowired
	MockMvc mockMvc;

	@MockitoBean
	EmailLookupService emailLookupService;

	@Test
	void registeredEmail_returns200True() throws Exception {
		when(emailLookupService.isEmailRegistered(eq("a@b.com"))).thenReturn(true);

		mockMvc.perform(get("/auth/email-exists").param("email", "a@b.com"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.exists").value(true));
	}

	@Test
	void unregisteredEmail_returns200False() throws Exception {
		when(emailLookupService.isEmailRegistered(eq("ghost@b.com"))).thenReturn(false);

		mockMvc.perform(get("/auth/email-exists").param("email", "ghost@b.com"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.exists").value(false));
	}
}
