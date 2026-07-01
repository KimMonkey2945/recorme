package com.recordapp.domain.device.controller;

import com.recordapp.domain.device.dto.RegisterDeviceTokenRequest;
import com.recordapp.domain.device.service.DeviceTokenService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.security.SecurityUser;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 기기 토큰 API. 컨텍스트 경로(/api/v1) 하위 /devices.
 * 본인 식별은 인증 principal 의 userId 로만 수행한다(요청 바디·경로에 사용자 식별자 없음, IDOR 차단).
 * 등록/해제는 멱등이라 항상 200 으로 응답한다(신규/갱신 구분 불필요).
 */
@RestController
@RequestMapping("/devices")
public class DeviceTokenController {

	private final DeviceTokenService deviceTokenService;

	public DeviceTokenController(DeviceTokenService deviceTokenService) {
		this.deviceTokenService = deviceTokenService;
	}

	/** POST /devices/tokens — 기기 토큰 등록/갱신(upsert, 멱등). */
	@PostMapping("/tokens")
	public ApiResponse<Void> register(
			@AuthenticationPrincipal SecurityUser principal,
			@Valid @RequestBody RegisterDeviceTokenRequest request) {
		deviceTokenService.register(principal.userId(), request);
		return ApiResponse.ok();
	}

	/** DELETE /devices/tokens?token=... — 기기 토큰 해제(로그아웃 등, 멱등). */
	@DeleteMapping("/tokens")
	public ApiResponse<Void> unregister(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam String token) {
		deviceTokenService.unregister(principal.userId(), token);
		return ApiResponse.ok();
	}
}
