package com.recordapp.infra.push;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 외부 호출 없이 로그만 남기는 {@link PushService} 구현.
 * 자격증명 미설정(로컬/CI) 시 {@code PushConfig}가 자동 선택한다(무키 동작 보장).
 * 모든 토큰을 성공으로 간주하고 무효 토큰은 없다고 본다.
 */
public class StubPushService implements PushService {

	private static final Logger log = LoggerFactory.getLogger(StubPushService.class);

	@Override
	public PushResult send(List<String> tokens, PushMessage message) {
		int count = (tokens == null) ? 0 : tokens.size();
		log.info("[StubPush] 발송 생략 tokens={} title={}", count, message.title());
		return new PushResult(count, List.of());
	}
}
