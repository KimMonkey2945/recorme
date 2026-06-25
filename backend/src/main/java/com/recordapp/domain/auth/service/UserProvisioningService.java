package com.recordapp.domain.auth.service;

import com.recordapp.domain.user.dto.UserJitCommand;
import com.recordapp.domain.user.mapper.UserMapper;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SecurityUser;
import com.recordapp.global.security.SupabaseClaims;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Supabase JWT 클레임으로 내부 users 행을 확보(JIT 프로비저닝)한다.
 * supabase_uid 매핑이 있으면 그대로, 없으면 자동 가입한다.
 * 이메일·소셜 가입을 구분하지 않고 동일 경로로 처리한다(provider 미참조).
 */
@Service
public class UserProvisioningService {

	private static final Logger log = LoggerFactory.getLogger(UserProvisioningService.class);

	private final UserMapper userMapper;

	public UserProvisioningService(UserMapper userMapper) {
		this.userMapper = userMapper;
	}

	/**
	 * supabase_uid로 내부 사용자를 확보한다. 없으면 INSERT(ON CONFLICT DO NOTHING)로 race-safe 가입.
	 * 동시 최초요청 2건이 와도 users 행은 1개만 생성된다.
	 */
	@Transactional
	public SecurityUser provision(SupabaseClaims claims) {
		String supabaseUid = claims.sub();
		if (supabaseUid == null || supabaseUid.isBlank()) {
			throw new BusinessException(ErrorCode.INVALID_TOKEN);
		}

		// 1) 기존 매핑 우선
		Long existingId = userMapper.findIdBySupabaseUid(supabaseUid);
		if (existingId != null) {
			return new SecurityUser(existingId, supabaseUid);
		}

		// 2) JIT 가입(클레임 폴백으로 닉네임·아바타·이메일 구성)
		String nickname = claims.resolveNickname();
		String avatarUrl = claims.resolveAvatarUrl();
		String email = claims.resolveEmail();

		Long newId = insertJit(new UserJitCommand(supabaseUid, nickname, email, avatarUrl), supabaseUid);
		if (newId != null) {
			return new SecurityUser(newId, supabaseUid);
		}

		// 3) 동시 최초요청으로 우리 INSERT가 DO NOTHING 됨 → 상대 트랜잭션 행을 재조회
		Long racedId = userMapper.findIdBySupabaseUid(supabaseUid);
		if (racedId == null) {
			log.error("JIT 프로비저닝 후 사용자 조회 실패: supabaseUid={}", supabaseUid);
			throw new BusinessException(ErrorCode.INTERNAL_ERROR);
		}
		return new SecurityUser(racedId, supabaseUid);
	}

	/**
	 * INSERT 시도. 활성 이메일 부분 유니크(다른 supabase_uid가 같은 email 보유) 충돌 시
	 * 이메일은 선택 정보이므로 email 없이 1회 재시도해 로그인을 막지 않는다.
	 *
	 * @return 생성된 PK. supabase_uid 충돌로 INSERT가 무시되면 null
	 */
	private Long insertJit(UserJitCommand command, String supabaseUid) {
		try {
			userMapper.insertOnConflictNothing(command);
			return command.getId();
		} catch (DuplicateKeyException e) {
			// uq_users_email_active 충돌(동일 활성 이메일을 가진 다른 계정 존재)
			log.warn("JIT 가입 이메일 충돌 → email 없이 재시도: supabaseUid={}", supabaseUid);
			UserJitCommand retry = new UserJitCommand(
					supabaseUid, command.getNickname(), null, command.getProfileImageUrl());
			userMapper.insertOnConflictNothing(retry);
			return retry.getId();
		}
	}
}
