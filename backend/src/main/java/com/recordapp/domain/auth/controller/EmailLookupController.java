package com.recordapp.domain.auth.controller;

import com.recordapp.domain.auth.dto.EmailExistsResponse;
import com.recordapp.domain.auth.service.EmailLookupService;
import com.recordapp.global.common.ApiResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 비인증 이메일 조회 API. 컨텍스트 경로(/api/v1) 하위 /auth.
 *
 * <p>비밀번호 찾기 화면(비로그인)에서 미가입 이메일을 사전 안내하기 위한 공개 엔드포인트.
 * 가입 여부를 노출하므로 이메일 열거가 가능하다(의도적 트레이드오프 — {@link EmailLookupService} 참고).
 * SecurityConfig에서 이 경로만 permitAll로 허용한다.
 */
@RestController
public class EmailLookupController {

	private final EmailLookupService emailLookupService;

	public EmailLookupController(EmailLookupService emailLookupService) {
		this.emailLookupService = emailLookupService;
	}

	/** GET /auth/email-exists?email=... — 해당 이메일로 가입한 활성 회원 존재 여부. */
	@GetMapping("/auth/email-exists")
	public ApiResponse<EmailExistsResponse> emailExists(@RequestParam("email") String email) {
		boolean exists = emailLookupService.isEmailRegistered(email);
		return ApiResponse.ok(new EmailExistsResponse(exists));
	}
}
