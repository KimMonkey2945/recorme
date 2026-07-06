package com.recordapp.domain.diary.dto;

import java.time.LocalDate;

/**
 * 피드 카드 탭 시 전문 조회 응답(GET /feed/{id}, viewer-aware).
 * 본인 글은 상태 무관, 그 외는 확정(DRAFT 아님)·활성·볼 수 있는(PUBLIC 또는 FRIENDS-친구) 글만.
 * 작성자 표시 정보 + 본문(Delta) + 감정 테마를 담는다(공유 링크와 달리 내부 id·공감 요약 포함).
 *
 * <p>reactionCount/reactedByMe 는 Task 015-4(공감)에서 실제 집계로 채워진다(그 전엔 0/false).
 */
public record FeedDetailResponse(
		Long id,
		String authorUuid,
		String authorNickname,
		String authorProfileImageUrl,
		String content,
		String contentText,
		LocalDate writtenDate,
		String visibility,
		String primaryEmotion,
		String backgroundColor,
		String textColor,
		String accentColor,
		String aiComment,
		String aiTitle,
		String moodEmoji,
		int reactionCount,
		boolean reactedByMe) {
}
