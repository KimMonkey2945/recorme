package com.recordapp.infra.llm;

/**
 * 외부 호출 없이 결정적 NEUTRAL 응답을 반환하는 {@link LlmClient} 구현.
 * 키 미설정(로컬/CI) 시 {@code LlmConfig}가 자동 선택한다.
 */
public class StubLlmClient implements LlmClient {

	/** 감정 분석 폴백과 동일한 NEUTRAL 고정 JSON(스키마 적용 결과 형태). */
	private static final String NEUTRAL_JSON = """
			{"primaryEmotion":"NEUTRAL","scores":{"NEUTRAL":1.0},\
			"backgroundColor":"#F7F5F0","textColor":"#232228","accentColor":"#6C5CE0",\
			"aiComment":"","aiTitle":"","moodEmoji":"🙂"}""";

	@Override
	public LlmResponse complete(LlmRequest request) {
		String model = (request.model() != null) ? request.model() : "stub";
		return new LlmResponse(NEUTRAL_JSON, model, 0, 0);
	}
}
