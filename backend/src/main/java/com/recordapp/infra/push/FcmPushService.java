package com.recordapp.infra.push;

import com.google.firebase.messaging.BatchResponse;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.MulticastMessage;
import com.google.firebase.messaging.Notification;
import com.google.firebase.messaging.SendResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * FCM 실발송 {@link PushService} 구현. {@link FirebaseMessaging#sendEachForMulticast}로 멀티캐스트 발송한다.
 * 자격증명이 있을 때만 {@code PushConfig}가 이 빈을 선택한다.
 *
 * <p>응답을 토큰별로 순회해 영구 무효({@link MessagingErrorCode#UNREGISTERED}/
 * {@link MessagingErrorCode#INVALID_ARGUMENT})만 회수 대상으로 수집한다 —
 * 그 외 일시 오류(네트워크·쿼터·서버 오류)는 토큰을 보존해 다음 발송에서 재시도되게 한다.
 */
public class FcmPushService implements PushService {

	private static final Logger log = LoggerFactory.getLogger(FcmPushService.class);

	private final FirebaseMessaging firebaseMessaging;

	public FcmPushService(FirebaseMessaging firebaseMessaging) {
		this.firebaseMessaging = firebaseMessaging;
	}

	@Override
	public PushResult send(List<String> tokens, PushMessage message) {
		if (tokens == null || tokens.isEmpty()) {
			return new PushResult(0, List.of());
		}

		MulticastMessage.Builder builder = MulticastMessage.builder()
				.addAllTokens(tokens)
				.setNotification(Notification.builder()
						.setTitle(message.title())
						.setBody(message.body())
						.build());
		Map<String, String> data = message.data();
		if (data != null && !data.isEmpty()) {
			builder.putAllData(data);
		}

		BatchResponse response;
		try {
			response = firebaseMessaging.sendEachForMulticast(builder.build());
		} catch (FirebaseMessagingException e) {
			// 요청 전체 실패(자격증명·네트워크 등) — 토큰을 무효로 보지 않고 보존해 재시도되게 한다.
			log.warn("FCM 멀티캐스트 발송 실패(전체) count={}", tokens.size(), e);
			return new PushResult(0, List.of());
		}

		// 응답은 tokens 와 동일 순서로 정렬된다 — 인덱스로 실패 토큰을 역참조한다.
		List<SendResponse> responses = response.getResponses();
		List<String> invalidTokens = new ArrayList<>();
		for (int i = 0; i < responses.size(); i++) {
			SendResponse each = responses.get(i);
			if (each.isSuccessful()) {
				continue;
			}
			MessagingErrorCode code = each.getException() == null ? null
					: each.getException().getMessagingErrorCode();
			if (code == MessagingErrorCode.UNREGISTERED || code == MessagingErrorCode.INVALID_ARGUMENT) {
				invalidTokens.add(tokens.get(i)); // 영구 무효 → 회수 대상
			}
			// 그 외 일시 오류는 토큰 보존(수집하지 않음).
		}

		log.info("FCM 멀티캐스트 발송 완료 success={} failure={} invalid={}",
				response.getSuccessCount(), response.getFailureCount(), invalidTokens.size());
		return new PushResult(response.getSuccessCount(), invalidTokens);
	}
}
