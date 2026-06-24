package com.recordapp.global.security;

/**
 * 인증된 사용자 principal. JWT에서 추출한 내부 userId와 외부 노출용 uuid를 담는다.
 * Controller에서 @AuthenticationPrincipal SecurityUser로 주입받아 사용한다.
 */
public record SecurityUser(Long userId, String uuid) {
}
