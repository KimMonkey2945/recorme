package com.recordapp.domain.auth.service;

import com.recordapp.domain.user.mapper.UserMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 이메일 가입 여부 조회 서비스.
 *
 * <p>⚠️ 이 조회는 비인증으로 노출되므로 <b>이메일 열거(enumeration)</b>가 가능하다.
 * 비밀번호 재설정 UX(미가입 안내)를 위해 의도적으로 수용한 트레이드오프이며,
 * 남용 방지가 필요하면 이 지점에 rate-limit을 둔다.
 */
@Service
public class EmailLookupService {

	private final UserMapper userMapper;

	public EmailLookupService(UserMapper userMapper) {
		this.userMapper = userMapper;
	}

	/** 해당 이메일로 가입한 활성 회원이 있는지. 빈/공백 이메일은 false. */
	@Transactional(readOnly = true)
	public boolean isEmailRegistered(String email) {
		if (email == null) {
			return false;
		}
		String normalized = email.trim();
		if (normalized.isEmpty()) {
			return false;
		}
		return userMapper.existsActiveByEmail(normalized);
	}
}
