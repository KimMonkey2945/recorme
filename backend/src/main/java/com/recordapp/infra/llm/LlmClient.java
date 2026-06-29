package com.recordapp.infra.llm;

/**
 * 멀티모달 LLM 호출 추상화. provider(Claude/그 외)를 격리해 구현체를 교체할 수 있게 한다.
 * (스토리지 {@code StorageService}·음악 {@code MusicSource}와 동일한 인프라 격리 패턴.)
 *
 * <p>예외는 그대로 던진다 — 폴백/재분석 정책은 상위 호출자(감정 분석 서비스)가 담당한다.
 */
public interface LlmClient {

	/**
	 * 단일 메시지 요청을 보내고 모델 응답을 반환한다.
	 *
	 * @param request 시스템/사용자 프롬프트·이미지·모델·토큰·(선택)JSON 스키마
	 * @return 모델 출력 텍스트와 사용 토큰 메타
	 */
	LlmResponse complete(LlmRequest request);
}
