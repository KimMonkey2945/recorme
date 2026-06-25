package com.recordapp.domain.user.controller;

import com.recordapp.domain.user.dto.UpdateProfileRequest;
import com.recordapp.domain.user.dto.UserProfileResponse;
import com.recordapp.domain.user.service.UserService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.security.SecurityUser;
import jakarta.validation.Valid;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

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

	/** PUT /users/me — 내 프로필 수정(닉네임·자기소개). 프로필 이미지는 별도 엔드포인트에서 갱신. */
	@PutMapping("/me")
	public ApiResponse<UserProfileResponse> updateMyProfile(
			@AuthenticationPrincipal SecurityUser principal,
			@Valid @RequestBody UpdateProfileRequest request) {
		return ApiResponse.ok(userService.updateProfile(principal.userId(), request));
	}

	/**
	 * POST /users/me/avatar — 프로필 이미지 업로드(multipart, part name="file").
	 * 검증·저장·DB 갱신을 즉시 수행하고 갱신된 프로필을 반환한다.
	 */
	@PostMapping(value = "/me/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
	public ApiResponse<UserProfileResponse> uploadMyAvatar(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestPart("file") MultipartFile file) {
		return ApiResponse.ok(userService.updateAvatar(principal.userId(), file));
	}
}
