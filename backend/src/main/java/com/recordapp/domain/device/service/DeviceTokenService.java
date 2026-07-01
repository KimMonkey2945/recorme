package com.recordapp.domain.device.service;

import com.recordapp.domain.device.dto.RegisterDeviceTokenRequest;
import com.recordapp.domain.device.mapper.DeviceTokenMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 기기 토큰 서비스. 소유권은 항상 SecurityContext 의 userId 로만 식별한다(IDOR 차단).
 * 토큰은 전역 유일이라 등록은 upsert 로 소유를 재귀속하고, 해제는 본인 소유 토큰만 삭제한다.
 */
@Service
public class DeviceTokenService {

	private final DeviceTokenMapper deviceTokenMapper;

	public DeviceTokenService(DeviceTokenMapper deviceTokenMapper) {
		this.deviceTokenMapper = deviceTokenMapper;
	}

	/**
	 * 기기 토큰 등록/갱신. 같은 토큰이 이미 있으면(타 계정 포함) 소유를 현재 사용자로 이전한다.
	 * 멱등하므로 앱이 로그인/기동마다 안전하게 호출할 수 있다.
	 */
	@Transactional
	public void register(Long userId, RegisterDeviceTokenRequest req) {
		deviceTokenMapper.upsert(userId, req.token(), req.platform().name());
	}

	/** 기기 토큰 해제(로그아웃 등). 본인 소유 토큰만 삭제되며, 없거나 타인 소유면 무동작(멱등). */
	@Transactional
	public void unregister(Long userId, String token) {
		deviceTokenMapper.deleteByToken(userId, token);
	}
}
