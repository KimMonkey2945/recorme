package com.recordapp.domain.auth.dto;

/**
 * 이메일 가입 여부 조회 응답.
 * { "exists": true|false }
 */
public record EmailExistsResponse(boolean exists) {
}
