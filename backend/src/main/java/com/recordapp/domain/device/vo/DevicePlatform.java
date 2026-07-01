package com.recordapp.domain.device.vo;

/**
 * 기기 플랫폼. V10 {@code chk_device_tokens_platform} CHECK 와 동일 집합.
 * enum 이름을 그대로 DB VARCHAR 값으로 저장한다(ANDROID/IOS/WEB).
 */
public enum DevicePlatform {
	ANDROID,
	IOS,
	WEB
}
