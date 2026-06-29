package com.recordapp.domain.diary.dto;

import com.recordapp.domain.diary.DiaryConstraints;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 기록 본문/공개범위 수정 요청. writtenDate 는 변경하지 않는다(하루 1기록 기준 날짜 고정).
 * 순수 텍스트({@code contentText}) 변경 시 서비스/SQL 에서 analysis_status 를 PENDING 으로 되돌려 재분석을
 * 트리거한다(서식·이미지만 바뀌면 재분석 불필요). visibility 는 nullable 허용.
 *
 * <p>{@code content} 는 리치 텍스트(Quill Delta JSON 문자열, 인라인 이미지 포함)이며 길이 제약을 두지 않는다.
 */
public record UpdateDiaryRequest(
		@NotBlank String content,
		@NotBlank @Size(max = DiaryConstraints.CONTENT_MAX) String contentText,
		String visibility) {
}
