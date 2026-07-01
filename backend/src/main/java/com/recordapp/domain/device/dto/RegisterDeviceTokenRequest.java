package com.recordapp.domain.device.dto;

import com.recordapp.domain.device.vo.DevicePlatform;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/**
 * 기기 토큰 등록 요청. 앱이 FCM SDK로 발급받은 등록 토큰과 플랫폼을 함께 보낸다.
 * 소유권은 SecurityContext 의 userId 로만 식별하므로 바디에 사용자 식별자를 두지 않는다(IDOR 차단).
 * 토큰은 전역 유일이라 재로그인/재설치 시 upsert 로 소유가 이전된다.
 *
 * @param token    FCM 등록 토큰(비어 있을 수 없음)
 * @param platform 기기 플랫폼(ANDROID/IOS/WEB)
 */
public record RegisterDeviceTokenRequest(
		@NotBlank String token,
		@NotNull DevicePlatform platform) {
}
