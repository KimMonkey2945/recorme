package com.recordapp.domain.emotion.dto;

import com.recordapp.domain.emotion.Emotion;
import java.util.Map;

/**
 * 일기 1건의 멀티모달 감정 분석 산출물. LLM 자유 생성(감정·색·코멘트·제목·이모지)을 담아
 * 후속(012-D)에서 {@code diaries} 분석 컬럼으로 저장한다.
 *
 * @param primaryEmotion  대표 감정
 * @param scores          감정별 점수 분포(키: 감정 코드, 값: 0~1, 합≈1.0)
 * @param backgroundColor 배경색 #RRGGBB
 * @param textColor       본문 글자색 #RRGGBB(최종 가독성 보정은 앱이 담당)
 * @param accentColor     강조색 #RRGGBB
 * @param aiComment       AI 공감 코멘트(한국어 한두 문장, ≤120자로 잘림)
 * @param aiTitle         AI 생성 제목(한국어, ≤20자)
 * @param moodEmoji       분위기 이모지 1개
 */
public record DiaryAnalysisResult(
		Emotion primaryEmotion,
		Map<String, Double> scores,
		String backgroundColor,
		String textColor,
		String accentColor,
		String aiComment,
		String aiTitle,
		String moodEmoji) {

	/**
	 * NEUTRAL 기본 팔레트. JSON 파싱 실패/응답 비정상/LLM 분석 실패 시의 최종 폴백이며,
	 * {@code Emotion.NEUTRAL} 팔레트 및 {@code StubLlmClient} 의 고정 JSON 과 값이 일치한다.
	 */
	public static DiaryAnalysisResult neutralFallback() {
		return new DiaryAnalysisResult(
				Emotion.NEUTRAL,
				Map.of("NEUTRAL", 1.0),
				"#F7F5F0",
				"#232228",
				"#6C5CE0",
				"",
				"",
				"🙂");
	}
}
