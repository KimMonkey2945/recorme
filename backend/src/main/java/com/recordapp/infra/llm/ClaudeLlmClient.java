package com.recordapp.infra.llm;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.JsonValue;
import com.anthropic.models.messages.Base64ImageSource;
import com.anthropic.models.messages.ContentBlock;
import com.anthropic.models.messages.ContentBlockParam;
import com.anthropic.models.messages.ImageBlockParam;
import com.anthropic.models.messages.JsonOutputFormat;
import com.anthropic.models.messages.Message;
import com.anthropic.models.messages.MessageCreateParams;
import com.anthropic.models.messages.OutputConfig;
import com.anthropic.models.messages.TextBlock;
import com.anthropic.models.messages.TextBlockParam;
import com.anthropic.models.messages.Usage;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

/**
 * 공식 Anthropic Java SDK 기반 {@link LlmClient} 구현(Claude).
 *
 * <p>클라이언트는 생성자에서 1회 생성해 보관한다(thread-safe). 재시도는 SDK 기본/설정값에 위임하고,
 * 예외는 그대로 던진다 — 폴백은 상위 호출자(감정 분석 서비스) 책임.
 */
public class ClaudeLlmClient implements LlmClient {

	private final AnthropicClient client;
	private final LlmProperties props;

	public ClaudeLlmClient(LlmProperties props) {
		this.props = props;
		this.client = AnthropicOkHttpClient.builder()
				.apiKey(props.apiKey())
				.maxRetries(props.maxRetries())
				.build();
	}

	@Override
	public LlmResponse complete(LlmRequest request) {
		String model = (request.model() != null) ? request.model() : props.model();

		// 사용자 메시지 블록: 텍스트 + (선택)이미지들
		List<ContentBlockParam> blocks = new ArrayList<>();
		blocks.add(ContentBlockParam.ofText(
				TextBlockParam.builder().text(request.userText()).build()));
		for (LlmImage image : request.images()) {
			blocks.add(toImageBlock(image));
		}

		MessageCreateParams.Builder builder = MessageCreateParams.builder()
				.model(model)
				.maxTokens(request.maxTokens())
				.addUserMessageOfBlockParams(blocks);

		if (request.systemPrompt() != null && !request.systemPrompt().isBlank()) {
			builder.system(request.systemPrompt());
		}

		// 구조화 JSON: 스키마가 있으면 해당 스키마로 출력을 강제한다(prefill 미사용).
		// Schema 객체는 JSON 스키마의 top-level 키들을 additionalProperties로 담는다.
		if (request.jsonSchema() != null) {
			JsonOutputFormat.Schema.Builder schemaBuilder = JsonOutputFormat.Schema.builder();
			request.jsonSchema().forEach((k, v) -> schemaBuilder.putAdditionalProperty(k, JsonValue.from(v)));
			builder.outputConfig(OutputConfig.builder()
					.format(JsonOutputFormat.builder().schema(schemaBuilder.build()).build())
					.build());
		}

		Message message = client.messages().create(builder.build());

		String text = message.content().stream()
				.map(ContentBlock::text)
				.filter(java.util.Optional::isPresent)
				.map(java.util.Optional::get)
				.map(TextBlock::text)
				.findFirst()
				.orElse("");

		Usage usage = message.usage();
		Integer inputTokens = (usage != null) ? (int) usage.inputTokens() : null;
		Integer outputTokens = (usage != null) ? (int) usage.outputTokens() : null;

		return new LlmResponse(text, model, inputTokens, outputTokens);
	}

	/** base64 image content block 조립. mediaType은 SDK enum으로 매핑한다. */
	private ContentBlockParam toImageBlock(LlmImage image) {
		String base64 = Base64.getEncoder().encodeToString(image.data());
		Base64ImageSource source = Base64ImageSource.builder()
				.data(base64)
				.mediaType(toMediaType(image.mediaType()))
				.build();
		return ContentBlockParam.ofImage(ImageBlockParam.builder().source(source).build());
	}

	private Base64ImageSource.MediaType toMediaType(String mediaType) {
		if (mediaType == null) {
			return Base64ImageSource.MediaType.IMAGE_JPEG;
		}
		return switch (mediaType.toLowerCase()) {
			case "image/png" -> Base64ImageSource.MediaType.IMAGE_PNG;
			case "image/webp" -> Base64ImageSource.MediaType.IMAGE_WEBP;
			case "image/gif" -> Base64ImageSource.MediaType.IMAGE_GIF;
			default -> Base64ImageSource.MediaType.IMAGE_JPEG;
		};
	}
}
