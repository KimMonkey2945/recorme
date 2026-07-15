package com.recordapp.domain.diary.dto;

import com.recordapp.domain.diary.DiaryConstraints;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PastOrPresent;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;

/**
 * 기록 저장(upsert) 요청. 하루 1기록 정책상 같은 날짜 재작성은 INSERT 가 아닌 UPDATE 로 처리된다.
 * visibility 는 nullable — 미지정 시 서비스/SQL 기본값 PRIVATE 적용.
 * 소유권은 SecurityContext 의 userId 로만 식별하므로 바디에 사용자 식별자를 두지 않는다(IDOR 차단).
 *
 * <p>{@code content} 는 리치 텍스트(Quill Delta JSON 문자열)로, 인라인 이미지를 포함한다 —
 * JSON 이라 길이 제약(@Size)을 두지 않는다. 길이 제약·미리보기·LLM 입력은 서식/이미지 마크업을 제거한
 * 순수 텍스트 {@code contentText} 가 담당한다(DB CHECK 1~500 과 동일 상수).
 *
 * <p>{@code confirm} 은 '오늘을 기억하기'(확정) 여부 — nullable 이며 미지정/false 면 등록(DRAFT,
 * 수정 가능·미분석), true 면 확정. 확정된 기록은 더 이상 수정할 수 없다. 확정 후 상태는 감정 분석
 * flag 에 따라 갈린다(off=즉시 DONE / on=PENDING→분석).
 *
 * <p>{@code emotion}·{@code emotionLabel} 은 사용자 직접 입력 감정(Task 024) — 둘 다 선택이며 상호 배타다.
 * {@code emotion} 은 프리셋 코드(JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL, {@code primary_emotion} 저장),
 * {@code emotionLabel} 은 자유 텍스트(≤20자, {@code emotion_label} 저장). 동시 지정 시 서비스가 EMOTION_CONFLICT.
 * (감정 분석 flag on 경로에선 LLM 이 감정을 채우므로 앱이 이 필드를 보내지 않는다.)
 */
public record SaveDiaryRequest(
		@NotBlank String content,
		@NotBlank @Size(max = DiaryConstraints.CONTENT_MAX) String contentText,
		@NotNull @PastOrPresent LocalDate writtenDate,
		String visibility,
		Boolean confirm,
		String emotion,
		@Size(max = 20) String emotionLabel) {

	/** 감정 미입력(기존 5-arg) 호환 생성자 — 감정 관련 두 필드를 null 로 위임한다. */
	public SaveDiaryRequest(String content, String contentText, LocalDate writtenDate,
			String visibility, Boolean confirm) {
		this(content, contentText, writtenDate, visibility, confirm, null, null);
	}
}
