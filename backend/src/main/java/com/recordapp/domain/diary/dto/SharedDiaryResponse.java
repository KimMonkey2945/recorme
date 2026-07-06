package com.recordapp.domain.diary.dto;

import java.time.LocalDate;

/**
 * 공유 링크 단건 조회 응답(GET /diaries/shared/{shareToken}). 비인증 공개 통로라
 * 내부 PK·소유자 식별자·공감 정보는 노출하지 않고, 작성자 표시명·본문·감정 테마만 담는다.
 * PRIVATE·DRAFT·삭제된 기록은 조회되지 않는다(서비스에서 차단).
 */
public record SharedDiaryResponse(
		String authorNickname,
		String authorProfileImageUrl,
		String content,
		String contentText,
		LocalDate writtenDate,
		String primaryEmotion,
		String backgroundColor,
		String textColor,
		String accentColor,
		String aiComment,
		String aiTitle,
		String moodEmoji) {
}
