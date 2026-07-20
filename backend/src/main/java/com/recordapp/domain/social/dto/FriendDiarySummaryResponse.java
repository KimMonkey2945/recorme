package com.recordapp.domain.social.dto;

import com.recordapp.domain.diary.dto.FriendDiarySummaryDay;
import java.util.List;

/**
 * 친구 둘러보기 — 월별 캘린더 요약 응답.
 *
 * <p>{@code days} 에는 친구에게 공개된 기록만 담긴다(visibility 가 FRIENDS·PUBLIC 인 확정 기록).
 * PRIVATE·DRAFT 기록은 애초에 내려가지 않으므로 앱에서는 <b>기록이 없는 날과 구분되지 않는다</b>
 * (요구사항: PRIVATE 는 "아예 없는 날처럼" 보인다).
 */
public record FriendDiarySummaryResponse(
		String yearMonth,
		List<FriendDiarySummaryDay> days) {
}
