package com.recordapp.infra.llm;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * LLM 설정(record.llm.*).
 *
 * <p>키는 환경변수로만 주입한다(코드·git 금지). apiKey가 비어 있으면 {@code LlmConfig}가
 * 자동으로 {@link StubLlmClient}를 선택해 로컬/CI 무키 동작을 보장한다.
 *
 * @param provider        provider 선택(gemini|ollama|claude|stub). 기본은 gemini(LLM_API_KEY 필수).
 * @param apiKey          LLM API 키(비어 있으면 Stub로 폴백. provider=ollama는 키 불필요)
 * @param baseUrl         provider REST 베이스 URL(예: Gemini generativelanguage v1beta)
 * @param model           기본 모델 ID(예: gemini-2.5-flash-lite, llava:7b, claude-haiku-4-5)
 * @param maxTokens       최대 출력 토큰
 * @param maxImages       한 요청에 첨부할 최대 이미지 수(상위 호출자가 제한에 사용)
 * @param imageMaxEdgePx  이미지 긴 변 다운스케일 한도(다운스케일은 호출자 책임, 여기선 설정만 보관)
 * @param mode            처리 방식(immediate|batch). batch 실호출은 후속 작업(012-D).
 * @param timeoutMs       호출 타임아웃(ms) — Gemini/Claude용
 * @param maxRetries      SDK 재시도 횟수
 * @param ollamaBaseUrl   로컬 Ollama REST 베이스 URL(기본 http://localhost:11434)
 * @param ollamaTimeoutMs Ollama 호출 타임아웃(ms) — CPU 비전 추론이 느려 기본 300000(5분)
 */
@ConfigurationProperties(prefix = "record.llm")
public record LlmProperties(
		@DefaultValue("gemini") String provider,
		String apiKey,
		@DefaultValue("https://generativelanguage.googleapis.com/v1beta") String baseUrl,
		@DefaultValue("gemini-2.5-flash-lite") String model,
		@DefaultValue("400") int maxTokens,
		@DefaultValue("3") int maxImages,
		@DefaultValue("512") int imageMaxEdgePx,
		@DefaultValue("immediate") String mode,
		@DefaultValue("30000") long timeoutMs,
		@DefaultValue("2") int maxRetries,
		@DefaultValue("http://localhost:11434") String ollamaBaseUrl,
		@DefaultValue("300000") long ollamaTimeoutMs) {
}
