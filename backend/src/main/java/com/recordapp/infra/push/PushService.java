package com.recordapp.infra.push;

import java.util.List;

/**
 * 서버 푸시 발송 추상화. provider(FCM 등)를 격리해 구현체를 교체·폴백할 수 있게 한다.
 * (LLM {@code LlmClient}·스토리지 {@code StorageService}와 동일한 인프라 격리 패턴.)
 *
 * <p>자격증명이 없으면 {@code PushConfig}가 {@link StubPushService}를 선택해 로컬/CI 무키 동작을 보장한다.
 */
public interface PushService {

	/**
	 * 여러 기기 토큰으로 동일 메시지를 멀티캐스트 발송한다.
	 *
	 * @param tokens  대상 FCM 등록 토큰들(빈 리스트면 무발송)
	 * @param message 발송할 메시지(제목·본문·data 페이로드)
	 * @return 성공 수와 회수 대상 무효 토큰을 담은 결과
	 */
	PushResult send(List<String> tokens, PushMessage message);
}
