package com.recordapp.domain.social.dto;

/**
 * 두 사용자 사이의 친구 관계 행(서비스 내부 판정용). 무방향 정렬쌍으로 단건 조회한다.
 * requesterId/addresseeId 로 방향(누가 신청했나)을, status/blockerId 로 상태를 판정한다.
 */
public record FriendshipRow(
		Long id,
		Long requesterId,
		Long addresseeId,
		String status,
		Long blockerId) {
}
