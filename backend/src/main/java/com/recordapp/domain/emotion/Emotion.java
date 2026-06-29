package com.recordapp.domain.emotion;

import java.util.Locale;

/**
 * 주감정 코드. V7 {@code emotion_types} 시드(JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL)와 정합한다.
 *
 * <p>각 감정은 LLM 응답의 색/이모지가 비정상일 때 클램프(대체)에 쓸 기본 팔레트를 함께 보유한다.
 * NEUTRAL 팔레트는 {@code DiaryAnalysisResult.neutralFallback()} 과 동일한 값이어야 한다.
 */
public enum Emotion {

	JOY("#FFF7E6", "#3A2E12", "#F5A623", "😊"),
	SADNESS("#EAF0F6", "#1F2A37", "#4A77B5", "😢"),
	ANGER("#FBEAE7", "#3A1A14", "#D64531", "😠"),
	CALM("#EAF4EE", "#1C2B22", "#4CA06A", "😌"),
	ANXIETY("#F2EEF7", "#25203A", "#7A5AC2", "😟"),
	NEUTRAL("#F7F5F0", "#232228", "#6C5CE0", "🙂");

	private final String backgroundColor;
	private final String textColor;
	private final String accentColor;
	private final String moodEmoji;

	Emotion(String backgroundColor, String textColor, String accentColor, String moodEmoji) {
		this.backgroundColor = backgroundColor;
		this.textColor = textColor;
		this.accentColor = accentColor;
		this.moodEmoji = moodEmoji;
	}

	public String backgroundColor() {
		return backgroundColor;
	}

	public String textColor() {
		return textColor;
	}

	public String accentColor() {
		return accentColor;
	}

	public String moodEmoji() {
		return moodEmoji;
	}

	/**
	 * 문자열 코드를 enum 으로 안전 변환한다. null·공백·대소문자 불일치·미정의 코드는 모두 {@link #NEUTRAL}.
	 * (LLM 응답이 임의 문자열을 줄 수 있으므로 예외 대신 폴백한다.)
	 */
	public static Emotion fromCodeOrNeutral(String code) {
		if (code == null || code.isBlank()) {
			return NEUTRAL;
		}
		try {
			return Emotion.valueOf(code.trim().toUpperCase(Locale.ROOT));
		} catch (IllegalArgumentException e) {
			return NEUTRAL;
		}
	}
}
