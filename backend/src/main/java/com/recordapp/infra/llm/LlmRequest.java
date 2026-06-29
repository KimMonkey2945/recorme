package com.recordapp.infra.llm;

import java.util.List;
import java.util.Map;

/**
 * LLM 단일 요청. 텍스트 + (선택)이미지 멀티모달 + (선택)구조화 JSON 스키마.
 *
 * @param systemPrompt 시스템 프롬프트(역할/지시)
 * @param userText     사용자 텍스트(분석 대상 본문 등)
 * @param images       비전 입력 이미지 목록(없으면 빈 리스트)
 * @param model        사용할 모델 ID(null이면 설정값 {@code record.llm.model} 사용)
 * @param maxTokens    최대 출력 토큰
 * @param jsonSchema   구조화 출력 JSON 스키마(null이면 일반 텍스트, 있으면 해당 스키마로 JSON 강제)
 */
public record LlmRequest(
		String systemPrompt,
		String userText,
		List<LlmImage> images,
		String model,
		int maxTokens,
		Map<String, Object> jsonSchema) {

	public LlmRequest {
		images = (images == null) ? List.of() : images;
	}
}
