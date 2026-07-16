package com.recordapp.domain.character.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * 월간 감정 분포 1행. 프리셋 감정과 직접 입력 감정을 한 리스트에 섞어 담는다(상호 배타).
 *
 * <p>NON_NULL 직렬화라 응답 형태가 종류에 따라 달라진다:
 * <ul>
 *   <li>프리셋: {@code {code, labelKo, count}} (label 생략)</li>
 *   <li>직접 입력: {@code {label, count}} (code·labelKo 생략)</li>
 * </ul>
 *
 * @param code    프리셋 감정 코드(직접 입력이면 null)
 * @param labelKo 프리셋 한국어 라벨(직접 입력이면 null)
 * @param label   직접 입력 감정 텍스트(프리셋이면 null)
 * @param count   해당 감정으로 확정한 기록 수
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record EmotionStat(
		String code,
		String labelKo,
		String label,
		int count) {

	/** 프리셋 감정 통계(code + 한국어 라벨). */
	public static EmotionStat preset(String code, String labelKo, int count) {
		return new EmotionStat(code, labelKo, null, count);
	}

	/** 직접 입력 감정 통계(자유 라벨). */
	public static EmotionStat custom(String label, int count) {
		return new EmotionStat(null, null, label, count);
	}
}
