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
 * 로컬 Ollama REST 기반 {@link LlmClient} 구현(과금 0 — 로컬 비전 모델, 예: {@code llava:7b}).
 *
 * <p>Spring {@link RestClient}로 {@code POST /api/chat}를 호출한다(새 의존성 없이 starter-web 내장).
 * 키가 필요 없으므로 {@code LlmConfig}는 키 검사 이전에 provider=ollama를 분기한다.
 * 클라이언트는 생성자에서 1회 생성해 보관한다(thread-safe). 예외는 그대로 던진다 —
 * 폴백/재분석은 상위 호출자(감정 분석 서비스) 책임.
 *
 * <p>CPU 비전 추론은 느리므로 read 타임아웃을 길게 잡는다({@code props.ollamaTimeoutMs()}, 기본 300000ms).
 * 응답은 {@code "format":"json"}으로 JSON 문자열을 강제해 {@code message.content}를 그대로
 * {@link LlmResponse#text()}에 담는다.
 */
public class OllamaLlmClient implements LlmClient {

	private final RestClient client;
	private final LlmProperties props;
	private final ObjectMapper objectMapper;

	public OllamaLlmClient(LlmProperties props, ObjectMapper objectMapper) {
		this.props = props;
		this.objectMapper = objectMapper;
		// 타임아웃: connect는 통상값, read는 길게(CPU 비전 추론 대기). 둘 다 ollamaTimeoutMs 적용.
		SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
		factory.setConnectTimeout(Duration.ofMillis(props.ollamaTimeoutMs()));
		factory.setReadTimeout(Duration.ofMillis(props.ollamaTimeoutMs()));
		this.client = RestClient.builder()
				.baseUrl(props.ollamaBaseUrl())
				.requestFactory(factory)
				.build();
	}

	@Override
	public LlmResponse complete(LlmRequest request) {
		String model = (request.model() != null) ? request.model() : props.model();
		int maxTokens = (request.maxTokens() > 0) ? request.maxTokens() : props.maxTokens();

		ObjectNode body = buildRequestBody(request, model, maxTokens);

		JsonNode response = client.post()
				.uri("/api/chat")
				.contentType(MediaType.APPLICATION_JSON)
				.body(body)
				.retrieve()
				.body(JsonNode.class);

		return parseResponse(response, model);
	}

	/**
	 * Ollama /api/chat 요청 바디 조립.
	 * stream=false(단일 응답), format="json"(JSON 강제), system 메시지는 systemPrompt가 있을 때만 추가,
	 * user 메시지의 images는 순수 base64 문자열 배열(이미지 없으면 키 생략).
	 */
	private ObjectNode buildRequestBody(LlmRequest request, String model, int maxTokens) {
		ObjectNode body = objectMapper.createObjectNode();
		body.put("model", model);
		body.put("stream", false);
		body.put("format", "json");
		// gemma4 등 thinking 지원 모델은 기본적으로 추론 토큰을 생성한다 → CPU 추론 지연·JSON 오염 방지.
		// 감정 분석은 결정적 JSON 추출이므로 사고 과정이 불필요. (비-thinking 모델에는 무시됨)
		body.put("think", false);

		ArrayNode messages = body.putArray("messages");

		String systemPrompt = request.systemPrompt();
		if (systemPrompt != null && !systemPrompt.isBlank()) {
			ObjectNode sys = messages.addObject();
			sys.put("role", "system");
			sys.put("content", systemPrompt);
		}

		ObjectNode user = messages.addObject();
		user.put("role", "user");
		user.put("content", request.userText());
		if (!request.images().isEmpty()) {
			// Ollama images는 mime/data: prefix 없는 순수 base64 문자열만 받는다.
			ArrayNode images = user.putArray("images");
			for (LlmImage image : request.images()) {
				images.add(Base64.getEncoder().encodeToString(image.data()));
			}
		}

		ObjectNode options = body.putObject("options");
		options.put("num_predict", maxTokens);
		options.put("temperature", 0.7);
		// 이미지(장당 ~256토큰)+시스템/유저 프롬프트가 안전히 들어가도록 컨텍스트 명시(기본값 truncation 회피).
		options.put("num_ctx", 8192);

		return body;
	}

	/**
	 * message.content(JSON 문자열) 추출. 비면 예외(상위 폴백 흡수).
	 * usage 토큰은 prompt_eval_count/eval_count가 있으면 매핑한다.
	 */
	private LlmResponse parseResponse(JsonNode response, String model) {
		if (response == null) {
			throw new IllegalStateException("Ollama 응답이 비어 있습니다(null).");
		}
		JsonNode contentNode = response.path("message").path("content");
		if (contentNode.isMissingNode() || contentNode.isNull()) {
			throw new IllegalStateException("Ollama 응답에 message.content가 없습니다: " + response);
		}
		String content = contentNode.asText();
		if (content.isBlank()) {
			throw new IllegalStateException("Ollama 응답 message.content가 비어 있습니다: " + response);
		}

		Integer inputTokens = response.has("prompt_eval_count") ? response.get("prompt_eval_count").asInt() : null;
		Integer outputTokens = response.has("eval_count") ? response.get("eval_count").asInt() : null;

		return new LlmResponse(content, model, inputTokens, outputTokens);
	}
}
