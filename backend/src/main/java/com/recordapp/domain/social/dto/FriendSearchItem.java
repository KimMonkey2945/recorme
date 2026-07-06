package com.recordapp.domain.social.dto;

/**
 * 친구 검색 결과 항목. relation 은 검색자 관점의 관계 상태 배지용:
 * NONE(관계 없음)/REQUESTED(내가 보낸 요청 대기)/INCOMING(상대가 보낸 요청 대기)/FRIEND(수락됨)/BLOCKED(차단).
 */
public record FriendSearchItem(
		String userUuid,
		String nickname,
		String profileImageUrl,
		String relation) {
}
