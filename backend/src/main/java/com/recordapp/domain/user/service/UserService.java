package com.recordapp.domain.user.service;

import com.recordapp.domain.user.dto.UpdateProfileRequest;
import com.recordapp.domain.user.dto.UserProfileResponse;
import com.recordapp.domain.user.mapper.UserMapper;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 프로필 조회/수정 서비스. 소유권은 항상 SecurityContext의 userId로만 식별한다(IDOR 차단).
 */
@Service
public class UserService {

	private final UserMapper userMapper;

	public UserService(UserMapper userMapper) {
		this.userMapper = userMapper;
	}

	/** 내 프로필 조회. JIT로 항상 존재하나 방어적으로 부재 시 USER_NOT_FOUND. */
	@Transactional(readOnly = true)
	public UserProfileResponse getProfile(Long userId) {
		UserProfileResponse profile = userMapper.findProfileByUserId(userId);
		if (profile == null) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		return profile;
	}

	/** 내 프로필 수정 후 갱신된 프로필 반환. bio·profileImageUrl 빈 문자열·공백은 NULL로 정규화. */
	@Transactional
	public UserProfileResponse updateProfile(Long userId, UpdateProfileRequest request) {
		String nickname = request.nickname().trim();
		String profileImageUrl = blankToNull(request.profileImageUrl());
		String bio = blankToNull(request.bio());

		int updated = userMapper.updateProfile(userId, nickname, profileImageUrl, bio);
		if (updated == 0) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		return userMapper.findProfileByUserId(userId);
	}

	/** null·빈 문자열·공백 → null. 그 외는 trim 결과. */
	private String blankToNull(String value) {
		if (value == null) {
			return null;
		}
		String trimmed = value.trim();
		return trimmed.isEmpty() ? null : trimmed;
	}
}
