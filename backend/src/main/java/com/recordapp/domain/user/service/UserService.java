package com.recordapp.domain.user.service;

import com.recordapp.domain.user.dto.UpdateProfileRequest;
import com.recordapp.domain.user.dto.UserProfileResponse;
import com.recordapp.domain.user.mapper.UserMapper;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.infra.storage.StorageService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

/**
 * 프로필 조회/수정 서비스. 소유권은 항상 SecurityContext의 userId로만 식별한다(IDOR 차단).
 */
@Service
public class UserService {

	private final UserMapper userMapper;
	private final StorageService storageService;

	public UserService(UserMapper userMapper, StorageService storageService) {
		this.userMapper = userMapper;
		this.storageService = storageService;
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

	/** 내 프로필 수정(닉네임·자기소개) 후 갱신된 프로필 반환. bio 빈 문자열·공백은 NULL로 정규화.
	 *  프로필 이미지는 건드리지 않는다(별도 updateAvatar 경로). */
	@Transactional
	public UserProfileResponse updateProfile(Long userId, UpdateProfileRequest request) {
		String nickname = request.nickname().trim();
		String bio = blankToNull(request.bio());

		int updated = userMapper.updateProfile(userId, nickname, bio);
		if (updated == 0) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		return userMapper.findProfileByUserId(userId);
	}

	/**
	 * 프로필 이미지 업로드 후 갱신된 프로필 반환.
	 * 파일 저장(외부 IO)은 트랜잭션 밖에서 수행하고 단일 UPDATE로 경로만 갱신한다.
	 * 실패 시 방금 저장한 파일을 보상 삭제하고, 성공 시 구 파일을 best-effort 정리한다.
	 */
	public UserProfileResponse updateAvatar(Long userId, MultipartFile file) {
		// 대상 존재 확인 + 구 이미지 경로 확보(부재 시 USER_NOT_FOUND)
		String oldUrl = getProfile(userId).profileImageUrl();

		String newUrl = storageService.store(file, "avatars"); // 검증 포함, 트랜잭션 밖
		int updated;
		try {
			updated = userMapper.updateProfileImage(userId, newUrl);
		} catch (RuntimeException e) {
			storageService.deleteByUrl(newUrl); // 갱신 실패 → 고아 파일 보상 삭제
			throw e;
		}
		if (updated == 0) {
			storageService.deleteByUrl(newUrl);
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}

		storageService.deleteByUrl(oldUrl); // 구 파일 정리(외부 URL이면 no-op)

		// UPDATE 성공과 재조회 사이에 소프트삭제되면 null 가능 → 빈 data 응답·NPE 방지.
		UserProfileResponse result = userMapper.findProfileByUserId(userId);
		if (result == null) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		return result;
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
