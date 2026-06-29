package com.recordapp.infra.llm;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.time.Duration;
import java.util.Base64;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * Google Gemini(generativeLanguage) REST 기반 {@link LlmClient} 구현(무료 티어).
 *
 * <p>Spring {@link RestClient}로 {@code generateContent}를 호출한다(새 의존성 없이 starter-web 내장).
 * 클라이언트는 생성자에서 1회 생성해 보관한다(thread-safe). 예외는 그대로 던진다 — 폴백/재분석은
 * 상위 호출자(감정 분석 서비스) 책임.
 *
 * <p>응답은 {@code responseMimeType=application/json}으로 JSON 문자열을 받아
 * {@code candidates[0].content.parts[0].text}를 그대로 {@link LlmResponse#text()}에 담는다.
 */
public class GeminiLlmClient implements LlmClient {

	private final RestClient client;
	private final LlmProperties props;
	private final ObjectMapper objectMapper;

	public GeminiLlmClient(LlmProperties props, ObjectMapper objectMapper) {
		this.props = props;
		this.objectMapper = objectMapper;
		// 타임아웃 반영: connect/read 모두 props.timeoutMs() 적용.
		SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
		factory.setConnectTimeout(Duration.ofMillis(props.timeoutMs()));
		factory.setReadTimeout(Duration.ofMillis(props.timeoutMs()));
		this.client = RestClient.builder()
				.baseUrl(props.baseUrl())
				.requestFactory(factory)
				.build();
	}

	@Override
	public LlmResponse complete(LlmRequest request) {
		String model = (request.model() != null) ? request.model() : props.model();
		int maxTokens = (request.maxTokens() > 0) ? request.maxTokens() : props.maxTokens();

		ObjectNode body = buildRequestBody(request, maxTokens);

		// POST /models/{model}:generateContent — 키는 헤더(x-goog-api-key)로만 전달.
		JsonNode response = client.post()
				.uri("/models/{model}:generateContent", model)
				.header("x-goog-api-key", props.apiKey())
				.contentType(MediaType.APPLICATION_JSON)
				.body(body)
				.retrieve()
				.body(JsonNode.class);

		return parseResponse(response, model);
	}

	/** Gemini generateContent 요청 바디 조립. system_instruction은 systemPrompt가 있을 때만 포함. */
	private ObjectNode buildRequestBody(LlmRequest request, int maxTokens) {
		ObjectNode body = objectMapper.createObjectNode();

		String systemPrompt = request.systemPrompt();
		if (systemPrompt != null && !systemPrompt.isBlank()) {
			ObjectNode sysParts = objectMapper.createObjectNode();
			ArrayNode parts = sysParts.putArray("parts");
			parts.addObject().put("text", systemPrompt);
			body.set("system_instruction", sysParts);
		}

		// contents[0] = user turn: 텍스트 + (선택)인라인 이미지들.
		ArrayNode contents = body.putArray("contents");
		ObjectNode userTurn = contents.addObject();
		userTurn.put("role", "user");
		ArrayNode userParts = userTurn.putArray("parts");
		userParts.addObject().put("text", request.userText());
		for (LlmImage image : request.images()) {
			ObjectNode part = userParts.addObject();
			ObjectNode inlineData = part.putObject("inline_data");
			inlineData.put("mime_type", image.mediaType());
			inlineData.put("data", Base64.getEncoder().encodeToString(image.data()));
		}

		// 구조화 출력: JSON MIME + (스키마가 있으면) responseSchema 로 출력 형식을 강제한다.
		ObjectNode genConfig = body.putObject("generationConfig");
		genConfig.put("responseMimeType", "application/json");
		genConfig.put("maxOutputTokens", maxTokens);
		if (request.jsonSchema() != null) {
			JsonNode schema = objectMapper.valueToTree(request.jsonSchema());
			stripUnsupportedSchemaKeys(schema);
			genConfig.set("responseSchema", schema);
		}

		return body;
	}

	/**
	 * Gemini {@code responseSchema}(OpenAPI 부분집합)가 지원하지 않는 JSON Schema 키를 재귀 제거한다.
	 * {@code additionalProperties}/{@code $schema} 등이 포함되면 400(INVALID_ARGUMENT)으로 거부되므로,
	 * 전달 전 정리한다. {@code type}(소문자)·{@code enum}·{@code pattern}·{@code minimum}/{@code maximum}·
	 * {@code maxLength}·{@code required}·{@code properties}·{@code items} 등은 그대로 지원되어 보존된다.
	 */
	static void stripUnsupportedSchemaKeys(JsonNode node) {
		if (node instanceof ObjectNode obj) {
			obj.remove("additionalProperties");
			obj.remove("$schema");
			obj.fields().forEachRemaining(e -> stripUnsupportedSchemaKeys(e.getValue()));
		} else if (node instanceof ArrayNode arr) {
			arr.forEach(GeminiLlmClient::stripUnsupportedSchemaKeys);
		}
	}

	/** candidates[0].content.parts[0].text 추출 + usageMetadata 토큰 매핑. 비면 예외(상위 폴백 흡수). */
	private LlmResponse parseResponse(JsonNode response, String model) {
		if (response == null) {
			throw new IllegalStateException("Gemini 응답이 비어 있습니다(null).");
		}
		JsonNode candidates = response.path("candidates");
		if (!candidates.isArray() || candidates.isEmpty()) {
			throw new IllegalStateException("Gemini 응답에 candidates가 없습니다: " + response);
		}
		JsonNode parts = candidates.get(0).path("content").path("parts");
		if (!parts.isArray() || parts.isEmpty()) {
			throw new IllegalStateException("Gemini 응답에 parts가 없습니다(차단/토큰 초과 가능): " + response);
		}
		JsonNode textNode = parts.get(0).path("text");
		if (textNode.isMissingNode() || textNode.isNull()) {
			throw new IllegalStateException("Gemini 응답 parts[0]에 text가 없습니다: " + response);
		}
		String text = textNode.asText();

		JsonNode usage = response.path("usageMetadata");
		Integer inputTokens = usage.has("promptTokenCount") ? usage.get("promptTokenCount").asInt() : null;
		Integer outputTokens = usage.has("candidatesTokenCount") ? usage.get("candidatesTokenCount").asInt() : null;

		return new LlmResponse(text, model, inputTokens, outputTokens);
	}
}
