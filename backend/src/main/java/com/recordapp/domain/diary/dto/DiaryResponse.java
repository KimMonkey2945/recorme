package com.recordapp.domain.diary.dto;

import java.time.LocalDate;

/**
 * 기록 단건 응답. 외부 노출 식별자는 share_token(공유 링크용)이며 내부 PK(id)도 함께 제공한다.
 *
 * <p>{@code content} 는 리치 텍스트(Quill Delta JSON 문자열)이며 인라인 이미지를 직접 임베드한다 —
 * 앱은 content Delta 에서 이미지를 렌더하므로 별도 이미지 목록을 두지 않는다.
 * {@code contentText} 는 서식/이미지 마크업을 제거한 순수 텍스트다(미리보기·길이 제약·LLM 입력용).
 *
 * <p>감정 분석 테마 필드(primaryEmotion~moodEmoji)는 앱이 배경색·글자색·강조색·AI 코멘트·이모지를
 * 렌더하는 데 쓴다. 분석 완료(analysisStatus=DONE)일 때만 채워지고, 그 외(DRAFT/PENDING/FAILED)는
 * NULL 로 내려간다 — 앱은 NULL 이면 기본(중립) 테마로 폴백한다.
 *
 * <p>{@code emotionLabel} 은 사용자 직접 입력 감정(Task 024) — 자유 텍스트(≤20자)다. 프리셋은
 * {@code primaryEmotion}(코드)으로, 자유 입력은 {@code emotionLabel}로 내려간다(상호 배타, 둘 다 NULL 가능).
 */
public record DiaryResponse(
		Long id,
		String shareToken,
		String content,
		String contentText,
		LocalDate writtenDate,
		String visibility,
		String analysisStatus,
		String primaryEmotion,
		String backgroundColor,
		String textColor,
		String accentColor,
		String aiComment,
		String aiTitle,
		String moodEmoji,
		String emotionLabel) {
}
