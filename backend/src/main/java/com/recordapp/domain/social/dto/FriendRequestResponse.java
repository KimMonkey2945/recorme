package com.recordapp.domain.social.dto;

/**
 * 친구 요청 결과. 보통 status=PENDING(요청 생성)이나,
 * 상대가 이미 나에게 보낸 요청이 있으면 자동 수락되어 status=ACCEPTED 로 돌아온다.
 */
public record FriendRequestResponse(Long requestId, String status) {
}
