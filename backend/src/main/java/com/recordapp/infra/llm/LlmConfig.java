package com.recordapp.infra.llm;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * LLM provider 빈 선택. {@code @ConditionalOnProperty}의 빈 문자열 함정을 피하려
 * 프로그램적으로 구현체를 고른다.
 *
 * <p>provider=ollama는 로컬·무키이므로 키 검사보다 먼저 분기해 {@link OllamaLlmClient}를 선택한다.
 * 그 외에는 키가 없으면 무조건 {@link StubLlmClient}(무키 로컬/CI 동작 보장),
 * 키가 있으면 provider에 따라 {@link GeminiLlmClient}/{@link ClaudeLlmClient}, 미지정/stub은 Stub.
 */
@Configuration
@EnableConfigurationProperties(LlmProperties.class)
public class LlmConfig {

	private static final Logger log = LoggerFactory.getLogger(LlmConfig.class);

	@Bean
	LlmClient llmClient(LlmProperties props, ObjectMapper objectMapper) {
		String provider = (props.provider() == null) ? "" : props.provider().toLowerCase();

		// 로컬 Ollama는 키가 필요 없으므로 키 검사 이전에 분기한다.
		if (provider.equals("ollama")) {
			log.info("LLM client = Ollama (model={}, baseUrl={})", props.model(), props.ollamaBaseUrl());
			return new OllamaLlmClient(props, objectMapper);
		}

		boolean noKey = props.apiKey() == null || props.apiKey().isBlank();
		if (noKey) {
			log.info("LLM client = Stub (apiKey absent, provider={})", props.provider());
			return new StubLlmClient();
		}
		return switch (provider) {
			case "gemini" -> {
				log.info("LLM client = Gemini (model={}, mode={})", props.model(), props.mode());
				yield new GeminiLlmClient(props, objectMapper);
			}
			case "claude" -> {
				log.info("LLM client = Claude (model={}, mode={})", props.model(), props.mode());
				yield new ClaudeLlmClient(props);
			}
			default -> {
				log.info("LLM client = Stub (unknown provider={})", props.provider());
				yield new StubLlmClient();
			}
		};
	}
}
