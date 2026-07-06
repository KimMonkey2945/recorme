package com.recordapp.domain.social.dto;

/**
 * 친구 목록 항목(커서 페이징). 커서는 friendship.id(관계 행 id).
 * 외부 노출 식별자는 상대의 uuid(내부 PK 비노출).
 */
public record FriendItem(
		Long friendshipId,
		String userUuid,
		String nickname,
		String profileImageUrl) {
}
