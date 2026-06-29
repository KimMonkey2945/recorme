package com.recordapp.infra.llm;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * {@link GeminiLlmClient#stripUnsupportedSchemaKeys} 검증.
 *
 * <p>Gemini responseSchema(OpenAPI 부분집합)는 {@code additionalProperties}/{@code $schema} 를
 * 거부하므로 중첩까지 모두 제거돼야 하고, 지원 키({@code type}/{@code enum}/{@code pattern}/
 * {@code minimum}/{@code maximum}/{@code maxLength}/{@code required}/{@code properties})는 보존돼야 한다.
 */
class GeminiLlmClientTest {

	private final ObjectMapper objectMapper = new ObjectMapper();

	@Test
	@DisplayName("additionalProperties/$schema 는 중첩 객체까지 모두 제거된다")
	void stripsUnsupportedKeysRecursively() {
		Map<String, Object> nested = new LinkedHashMap<>();
		nested.put("type", "object");
		nested.put("additionalProperties", false);
		nested.put("properties", Map.of("JOY", Map.of("type", "number")));

		Map<String, Object> schema = new LinkedHashMap<>();
		schema.put("$schema", "http://json-schema.org/draft-07/schema#");
		schema.put("type", "object");
		schema.put("additionalProperties", false);
		schema.put("properties", Map.of("scores", nested));

		JsonNode tree = objectMapper.valueToTree(schema);
		GeminiLlmClient.stripUnsupportedSchemaKeys(tree);

		assertThat(tree.has("additionalProperties")).isFalse();
		assertThat(tree.has("$schema")).isFalse();
		assertThat(tree.path("properties").path("scores").has("additionalProperties")).isFalse();
	}

	@Test
	@DisplayName("Gemini 가 지원하는 스키마 키는 보존된다")
	void preservesSupportedKeys() {
		Map<String, Object> schema = new LinkedHashMap<>();
		schema.put("type", "object");
		schema.put("additionalProperties", false);
		Map<String, Object> props = new LinkedHashMap<>();
		props.put("primaryEmotion", Map.of("type", "string", "enum", List.of("JOY", "SADNESS")));
		props.put("backgroundColor", Map.of("type", "string", "pattern", "^#[0-9A-Fa-f]{6}$"));
		props.put("score", Map.of("type", "number", "minimum", 0, "maximum", 1));
		props.put("aiTitle", Map.of("type", "string", "maxLength", 20));
		schema.put("properties", props);
		schema.put("required", List.of("primaryEmotion"));

		JsonNode tree = objectMapper.valueToTree(schema);
		GeminiLlmClient.stripUnsupportedSchemaKeys(tree);

		JsonNode p = tree.path("properties");
		assertThat(tree.path("type").asText()).isEqualTo("object");
		assertThat(tree.path("required")).hasSize(1);
		assertThat(p.path("primaryEmotion").path("enum")).hasSize(2);
		assertThat(p.path("backgroundColor").path("pattern").asText()).isEqualTo("^#[0-9A-Fa-f]{6}$");
		assertThat(p.path("score").path("minimum").asInt()).isZero();
		assertThat(p.path("score").path("maximum").asInt()).isOne();
		assertThat(p.path("aiTitle").path("maxLength").asInt()).isEqualTo(20);
	}
}
