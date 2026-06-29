package com.recordapp.infra.llm;

/**
 * LLM 응답.
 *
 * @param text         모델 출력 텍스트(스키마 적용 시 JSON 문자열)
 * @param model        실제 응답한 모델 ID
 * @param inputTokens  입력 토큰 수(없으면 null)
 * @param outputTokens 출력 토큰 수(없으면 null)
 */
public record LlmResponse(
		String text,
		String model,
		Integer inputTokens,
		Integer outputTokens) {
}
