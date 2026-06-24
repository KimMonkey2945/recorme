package com.recordapp.domain.auth.social;

import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * provider → SocialVerifier 라우팅. 등록된 모든 SocialVerifier 빈을 provider 키로 모은다.
 * 미지원 provider 요청 시 UNSUPPORTED_PROVIDER.
 * (현재 등록된 구현체가 없으므로 모든 resolve는 UNSUPPORTED — Phase 3에서 구현체 추가.)
 */
@Component
public class SocialVerifierRouter {

	private final Map<Provider, SocialVerifier> verifiers = new EnumMap<>(Provider.class);

	public SocialVerifierRouter(List<SocialVerifier> verifierBeans) {
		for (SocialVerifier verifier : verifierBeans) {
			verifiers.put(verifier.provider(), verifier);
		}
	}

	public SocialVerifier resolve(Provider provider) {
		SocialVerifier verifier = verifiers.get(provider);
		if (verifier == null) {
			throw new BusinessException(ErrorCode.UNSUPPORTED_PROVIDER);
		}
		return verifier;
	}
}
