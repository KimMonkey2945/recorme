package com.recordapp.domain.user.controller;

import com.recordapp.domain.user.dto.UpdateProfileRequest;
import com.recordapp.domain.user.dto.UserProfileResponse;
import com.recordapp.domain.user.service.UserService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.security.SecurityUser;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 내 프로필 API. 컨텍스트 경로(/api/v1) 하위 /users/me.
 * 본인 식별은 인증 principal의 userId로만 수행한다(요청 바디에 식별자 없음).
 */
@RestController
@RequestMapping("/users")
public class UserController {

	private final UserService userService;

	public UserController(UserService userService) {
		this.userService = userService;
	}

	/** GET /users/me — 현재 사용자 프로필 조회 */
	@GetMapping("/me")
	public ApiResponse<UserProfileResponse> getMyProfile(
			@AuthenticationPrincipal SecurityUser principal) {
		return ApiResponse.ok(userService.getProfile(principal.userId()));
	}

	/** PUT /users/me — 내 프로필 수정(닉네임·프로필 이미지·자기소개) */
	@PutMapping("/me")
	public ApiResponse<UserProfileResponse> updateMyProfile(
			@AuthenticationPrincipal SecurityUser principal,
			@Valid @RequestBody UpdateProfileRequest request) {
		return ApiResponse.ok(userService.updateProfile(principal.userId(), request));
	}
}
