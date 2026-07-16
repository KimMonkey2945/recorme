package com.recordapp.domain.character.dto;

/**
 * 월간 감정 집계 매퍼 원행(프리셋 + 직접 입력을 UNION 으로 한 번에 뽑는다).
 * 프리셋 행은 (code, labelKo) 만, 직접 입력 행은 (label) 만 채워진다.
 *
 * @param code    프리셋 감정 코드(직접 입력 행이면 null)
 * @param labelKo 프리셋 한국어 라벨(직접 입력 행이면 null)
 * @param label   직접 입력 감정 텍스트(프리셋 행이면 null)
 * @param count   집계 수
 */
public record EmotionCountRow(
		String code,
		String labelKo,
		String label,
		int count) {
}
