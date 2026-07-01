package com.recordapp.domain.resolution.service;

import com.recordapp.domain.device.mapper.DeviceTokenMapper;
import com.recordapp.infra.push.PushMessage;
import com.recordapp.infra.push.PushResult;
import com.recordapp.infra.push.PushService;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

/**
 * 작심삼일 푸시 발송 단일 경로. 토큰 팬아웃(user_id→토큰들) + 발송 + 무효 토큰 회수를 한곳에 모아
 * 성공 훅(ResolutionService)·실패 배치·리마인더 스케줄러가 공유한다(중복 제거).
 *
 * <p>모든 발송은 {@code @Async("pushExecutor")} 로 전용 스레드풀에서 수행한다 —
 * 외부 IO(FCM)를 트랜잭션·요청 스레드·스케줄러 드레인 루프 밖으로 밀어낸다.
 * 발송 예외는 로깅만 하고 삼킨다(호출자 상태 오염·롤백 유발 금지).
 */
@Component
public class ResolutionPushNotifier {

	private static final Logger log = LoggerFactory.getLogger(ResolutionPushNotifier.class);

	private final PushService pushService;
	private final DeviceTokenMapper deviceTokenMapper;

	public ResolutionPushNotifier(PushService pushService, DeviceTokenMapper deviceTokenMapper) {
		this.pushService = pushService;
		this.deviceTokenMapper = deviceTokenMapper;
	}

	/** 3일 완주 축하 푸시. completeToday 의 afterCommit 훅에서 호출된다(커밋 확정 후 발송). */
	@Async("pushExecutor")
	public void sendSuccess(long userId, long resolutionId) {
		send(userId, new PushMessage(
				"작심삼일 성공!",
				"3일 완주했어요. 연장할까요?",
				Map.of("type", "SUCCESS", "resolutionId", String.valueOf(resolutionId))));
	}

	/** 오늘 미완료 리마인더 푸시. 리마인더 스케줄러가 선점 커밋 후 대상별로 호출한다. */
	@Async("pushExecutor")
	public void sendReminder(long userId, long resolutionId, String title) {
		send(userId, new PushMessage(
				"작심삼일 리마인더",
				"오늘 '" + title + "' 아직 안 했어요",
				Map.of("type", "REMINDER", "resolutionId", String.valueOf(resolutionId))));
	}

	/** 도전 실패 알림 푸시. 자정 실패 배치가 ONGOING→FAILED 전이된 결심에 대해 호출한다(옵션). */
	@Async("pushExecutor")
	public void sendFailure(long userId, long resolutionId) {
		send(userId, new PushMessage(
				"작심삼일 실패",
				"아쉽지만 이번 도전은 실패했어요. 다시 시작해볼까요?",
				Map.of("type", "FAILED", "resolutionId", String.valueOf(resolutionId))));
	}

	/** 공통 팬아웃/발송/회수. 토큰 없으면 무발송, 무효 토큰은 회수, 예외는 경고 로깅만. */
	private void send(long userId, PushMessage message) {
		try {
			List<String> tokens = deviceTokenMapper.findTokensByUserId(userId);
			if (tokens.isEmpty()) {
				return;
			}
			PushResult result = pushService.send(tokens, message);
			if (!result.invalidTokens().isEmpty()) {
				deviceTokenMapper.deleteTokens(result.invalidTokens());
			}
		} catch (Exception e) {
			// 발송은 부가효과 — 실패해도 상태 전이(성공/실패/체크)는 이미 커밋됐으므로 로깅만 한다.
			log.warn("작심삼일 푸시 발송 실패 userId={} : {}", userId, e.toString());
		}
	}
}
