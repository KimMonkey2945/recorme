package com.recordapp.domain.emotion.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.domain.emotion.Emotion;
import com.recordapp.domain.emotion.dto.DiaryAnalysisResult;
import com.recordapp.infra.llm.LlmClient;
import com.recordapp.infra.llm.LlmImage;
import com.recordapp.infra.llm.LlmProperties;
import com.recordapp.infra.llm.LlmRequest;
import com.recordapp.infra.llm.LlmResponse;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * {@link LlmClient} 기반 멀티모달 감정 분석 구현. 구조화 JSON 스키마로 출력을 강제하고,
 * 응답을 검증·클램프해 {@link DiaryAnalysisResult} 로 변환한다.
 *
 * <p>견고성 원칙: 어떤 비정상(파싱 실패·필드 누락·형식 위반)도 예외로 전파하지 않는다.
 * 필드 단위는 해당 감정 기본 팔레트로 클램프하고, JSON 자체가 깨지면 통째로
 * {@link DiaryAnalysisResult#neutralFallback()} 으로 폴백한다.
 *
 * <p>JSON 키는 camelCase(DTO·{@code StubLlmClient}와 동일)를 1차로 쓰되, 파서는 snake_case 도
 * 폴백 인식해 프롬프트 규약을 약간 벗어난 응답에도 견딘다.
 */
@Service
public class LlmEmotionAnalyzer implements EmotionAnalyzer {

	private static final Logger log = LoggerFactory.getLogger(LlmEmotionAnalyzer.class);

	private static final Pattern HEX_COLOR = Pattern.compile("^#[0-9A-Fa-f]{6}$");
	private static final int COMMENT_MAX = 120;
	private static final int TITLE_MAX = 20;
	private static final String TEXT_COLOR_FALLBACK = "#232228";

	/** 6감정 코드(스키마 enum·scores 키). */
	private static final List<String> EMOTION_CODES =
			List.of("JOY", "SADNESS", "ANGER", "CALM", "ANXIETY", "NEUTRAL");

	private static final String SYSTEM_PROMPT = """
			너는 따뜻하고 공감 능력이 깊은 일기 감정 분석가다. 아래 JSON만 출력하라(설명·마크다운·코드펜스 금지).

			분석 태도:
			- 글을 끝까지 신중히 읽고, 표면적 단어가 아니라 글쓴이의 진짜 감정과 그날의 맥락을 헤아린다.
			- 6가지 감정(JOY, SADNESS, ANGER, CALM, ANXIETY, NEUTRAL)을 모두 고려해, 섞여 있는 감정을
			  scores에 분포로 반영한다. 한 감정에만 1.0을 몰지 말고 실제로 느껴지는 정도에 따라 나눠라.
			  애매하다고 NEUTRAL로 도피하지 말고, 근거가 있으면 가장 가까운 감정을 고른다.

			제약:
			- primaryEmotion: JOY, SADNESS, ANGER, CALM, ANXIETY, NEUTRAL 중 정확히 하나(scores 최고값과 일치)
			- backgroundColor, textColor, accentColor: #RRGGBB 형식(예: #F7F5F0)
			- moodEmoji: 그날의 분위기를 잘 담은 이모지 1개
			- aiComment: 글쓴이에게 건네는 한국어 한두 문장(100자 이내, 문장은 끝까지 완성). 진심으로 공감하고
			  다독이는 따뜻한 말투로, 일기 내용의 구체적인 부분을 짚어 성의 있게 적는다.
			  판에 박힌 말·평가·훈계·반복되는 표현은 피한다.
			- aiTitle: 그날을 함축하는 한국어 제목, 20자 이하
			- scores: 위 6개 감정 코드를 키로 한 0~1 점수, 합은 약 1.0
			- 글 우선 규칙: 이미지와 글(일기 본문)이 상충하거나 이미지 인식이 불확실하면,
			  글을 우선해 감정·색·코멘트·제목·이모지를 결정하고 이미지는 보조 단서로만 사용한다.""";

	private final LlmClient llmClient;
	private final LlmProperties props;
	private final ObjectMapper objectMapper;

	public LlmEmotionAnalyzer(LlmClient llmClient, LlmProperties props, ObjectMapper objectMapper) {
		this.llmClient = llmClient;
		this.props = props;
		this.objectMapper = objectMapper;
	}

	@Override
	public DiaryAnalysisResult analyze(String contentText, List<LlmImage> images) {
		try {
			LlmRequest request = new LlmRequest(
					SYSTEM_PROMPT,
					contentText == null ? "" : contentText,
					images,
					props.model(),
					props.maxTokens(),
					buildJsonSchema());
			LlmResponse response = llmClient.complete(request);
			return parse(response == null ? null : response.text());
		} catch (RuntimeException e) {
			// LLM 호출 자체 실패(네트워크/타임아웃 등)도 분석 실패로 흡수한다.
			log.warn("감정 분석 LLM 호출 실패 — NEUTRAL 폴백.", e);
			return DiaryAnalysisResult.neutralFallback();
		}
	}

	// ===== 구조화 출력 스키마 =====

	/**
	 * 응답 JSON Schema(Map). ClaudeLlmClient 가 output_config.format 으로 강제한다.
	 * 키는 camelCase(DTO·Stub 정합). 모든 필드 required, additionalProperties=false.
	 */
	private Map<String, Object> buildJsonSchema() {
		Map<String, Object> properties = new LinkedHashMap<>();
		properties.put("primaryEmotion", Map.of("type", "string", "enum", EMOTION_CODES));
		properties.put("scores", scoresSchema());
		properties.put("backgroundColor", hexColorSchema());
		properties.put("textColor", hexColorSchema());
		properties.put("accentColor", hexColorSchema());
		properties.put("aiComment", Map.of("type", "string", "maxLength", COMMENT_MAX));
		properties.put("aiTitle", Map.of("type", "string", "maxLength", TITLE_MAX));
		properties.put("moodEmoji", Map.of("type", "string"));

		Map<String, Object> schema = new LinkedHashMap<>();
		schema.put("type", "object");
		schema.put("properties", properties);
		schema.put("required", List.of(
				"primaryEmotion", "scores", "backgroundColor", "textColor",
				"accentColor", "aiComment", "aiTitle", "moodEmoji"));
		schema.put("additionalProperties", false);
		return schema;
	}

	private Map<String, Object> hexColorSchema() {
		return Map.of("type", "string", "pattern", "^#[0-9A-Fa-f]{6}$");
	}

	private Map<String, Object> scoresSchema() {
		Map<String, Object> scoreProps = new LinkedHashMap<>();
		for (String code : EMOTION_CODES) {
			scoreProps.put(code, Map.of("type", "number", "minimum", 0, "maximum", 1));
		}
		Map<String, Object> schema = new LinkedHashMap<>();
		schema.put("type", "object");
		schema.put("properties", scoreProps);
		schema.put("required", EMOTION_CODES);
		schema.put("additionalProperties", false);
		return schema;
	}

	// ===== 파싱·검증·클램프 =====

	private DiaryAnalysisResult parse(String json) {
		if (json == null || json.isBlank()) {
			return DiaryAnalysisResult.neutralFallback();
		}
		try {
			JsonNode root = objectMapper.readTree(json);
			if (!root.isObject()) {
				return DiaryAnalysisResult.neutralFallback();
			}

			Emotion primary = Emotion.fromCodeOrNeutral(text(root, "primaryEmotion", "primary_emotion"));

			String bg = clampColor(text(root, "backgroundColor", "background_color"), primary.backgroundColor());
			String accent = clampColor(text(root, "accentColor", "accent_color"), primary.accentColor());
			// text_color 는 모델 값을 쓰되 비정상이면 고정 폴백(최종 가독성은 앱이 보정).
			String textColor = clampColor(text(root, "textColor", "text_color"), TEXT_COLOR_FALLBACK);

			String comment = truncate(text(root, "aiComment", "ai_comment"), COMMENT_MAX);
			String title = truncate(text(root, "aiTitle", "ai_title"), TITLE_MAX);
			String emoji = firstNonBlank(text(root, "moodEmoji", "mood_emoji"), primary.moodEmoji());

			Map<String, Double> scores = parseScores(root.path("scores"), primary);

			return new DiaryAnalysisResult(primary, scores, bg, textColor, accent, comment, title, emoji);
		} catch (RuntimeException | com.fasterxml.jackson.core.JsonProcessingException e) {
			log.warn("감정 분석 응답 파싱 실패 — NEUTRAL 폴백. raw(앞 200자)={}", abbreviate(json), e);
			return DiaryAnalysisResult.neutralFallback();
		}
	}

	/** camelCase 우선, 없으면 snake_case 키로 텍스트 추출. 둘 다 없으면 null. */
	private String text(JsonNode root, String camel, String snake) {
		JsonNode n = root.path(camel);
		if (n.isMissingNode() || n.isNull()) {
			n = root.path(snake);
		}
		return n.isValueNode() ? n.asText(null) : null;
	}

	/** #RRGGBB 만 통과, 위반 시 폴백 색으로 클램프. */
	private String clampColor(String value, String fallback) {
		return (value != null && HEX_COLOR.matcher(value).matches()) ? value : fallback;
	}

	private String truncate(String value, int max) {
		if (value == null) {
			return "";
		}
		String trimmed = value.strip();
		return trimmed.length() > max ? trimmed.substring(0, max) : trimmed;
	}

	private String firstNonBlank(String value, String fallback) {
		return (value != null && !value.isBlank()) ? value.strip() : fallback;
	}

	/**
	 * scores 파싱: 유효 숫자(0~1 클램프)만 수집해 합으로 정규화한다. 비거나 합이 0이면
	 * 주감정에 1.0 을 부여한 기본값을 돌려준다.
	 */
	private Map<String, Double> parseScores(JsonNode scoresNode, Emotion primary) {
		Map<String, Double> raw = new LinkedHashMap<>();
		double sum = 0.0;
		if (scoresNode != null && scoresNode.isObject()) {
			var fields = scoresNode.fields();
			while (fields.hasNext()) {
				Map.Entry<String, JsonNode> e = fields.next();
				JsonNode v = e.getValue();
				if (v != null && v.isNumber()) {
					double d = clamp01(v.asDouble());
					if (d > 0.0) {
						raw.merge(e.getKey().trim().toUpperCase(java.util.Locale.ROOT), d, Double::sum);
						sum += d;
					}
				}
			}
		}
		if (raw.isEmpty() || sum <= 0.0) {
			return Map.of(primary.name(), 1.0);
		}
		Map<String, Double> normalized = new LinkedHashMap<>();
		for (Map.Entry<String, Double> e : raw.entrySet()) {
			normalized.put(e.getKey(), e.getValue() / sum);
		}
		return normalized;
	}

	private double clamp01(double d) {
		if (Double.isNaN(d) || d < 0.0) {
			return 0.0;
		}
		return Math.min(d, 1.0);
	}

	private String abbreviate(String s) {
		return s.length() <= 200 ? s : s.substring(0, 200);
	}
}
