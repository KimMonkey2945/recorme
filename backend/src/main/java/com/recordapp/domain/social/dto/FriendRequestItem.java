package com.recordapp.domain.social.dto;

import java.time.OffsetDateTime;

/**
 * 친구 요청 항목(받은/보낸 목록, 커서 페이징). 커서는 friendship.id(요청 행 id).
 * userUuid 는 상대(받은 요청이면 요청자, 보낸 요청이면 수신자)의 외부 식별자.
 */
public record FriendRequestItem(
		Long requestId,
		String userUuid,
		String nickname,
		String profileImageUrl,
		OffsetDateTime createdAt) {
}
