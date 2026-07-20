package com.recordapp.domain.diary.dto;

/**
 * 친구 둘러보기 — 캘린더 일자별 요약 1행(DiaryMapper.findFriendSummaryDays 반환 행).
 *
 * <p>본인용 {@link DiarySummaryDay} 와 같은 형태이되 <b>{@code diaryId} 를 추가로 싣는다</b>.
 * 본인 캘린더는 날짜를 탭하면 {@code GET /diaries/by-date/{date}} 로 id 를 다시 조회하지만
 * 그 API 는 본인 전용이라 친구에게 쓸 수 없다. 여기서 id 를 함께 내려 앱이 추가 왕복 없이
 * 곧바로 {@code /feed/diary/:id}(viewer-aware 상세)로 이동하게 한다.
 */
public record FriendDiarySummaryDay(
		Long diaryId,
		String date,
		String analysisStatus,
		String primaryEmotion,
		String moodEmoji) {
}
