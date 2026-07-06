package com.recordapp.domain.social.dto;

/**
 * 공감 추가/취소 응답. UI 즉시 동기화를 위해 갱신된 공감 수와 내 공감 여부를 함께 돌려준다.
 */
public record ReactionResponse(int reactionCount, boolean reacted) {
}
