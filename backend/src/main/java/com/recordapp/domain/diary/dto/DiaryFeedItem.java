package com.recordapp.domain.diary.dto;

import java.time.LocalDate;

/**
 * 피드 카드 항목(GET /feed). 전문(content)은 싣지 않고 감정 카드에 필요한 요약만 담는다 —
 * 작성자 표시 정보·무드 이모지·AI 제목·본문 미리보기(content_text 발췌)·감정색·공감 요약.
 * 커서는 diary id(DESC). 탭 시 GET /feed/{id}로 전문을 조회한다.
 *
 * <p>reactionCount/reactedByMe 는 Task 015-4(공감)에서 실제 집계로 채워진다.
 * 그 전(diary_reactions 테이블 부재)에는 매퍼가 0/false 리터럴로 내려준다.
 */
public record DiaryFeedItem(
		Long id,
		String authorUuid,
		String authorNickname,
		String authorProfileImageUrl,
		String moodEmoji,
		String aiTitle,
		String preview,
		LocalDate writtenDate,
		String visibility,
		String primaryEmotion,
		String backgroundColor,
		String accentColor,
		int reactionCount,
		boolean reactedByMe) {
}
