package com.recordapp.global.exception;

import org.springframework.http.HttpStatus;

/**
 * 비즈니스 에러 코드. enum 이름이 응답의 error.code, message가 기본 메시지.
 * GlobalExceptionHandler가 status로 HTTP 상태를 매핑한다.
 */
public enum ErrorCode {

	// 인증/인가
	UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "인증이 필요합니다."),
	INVALID_TOKEN(HttpStatus.UNAUTHORIZED, "유효하지 않은 토큰입니다."),
	EXPIRED_TOKEN(HttpStatus.UNAUTHORIZED, "만료된 토큰입니다."),
	FORBIDDEN(HttpStatus.FORBIDDEN, "접근 권한이 없습니다."),

	// 사용자
	USER_NOT_FOUND(HttpStatus.NOT_FOUND, "사용자를 찾을 수 없습니다."),

	// 일기
	DIARY_NOT_FOUND(HttpStatus.NOT_FOUND, "일기를 찾을 수 없습니다."),
	IMAGE_LIMIT_EXCEEDED(HttpStatus.CONFLICT, "사진은 일기당 최대 5장까지 첨부할 수 있습니다."),

	// 파일 업로드
	INVALID_FILE(HttpStatus.BAD_REQUEST, "허용되지 않는 파일입니다."),
	FILE_TOO_LARGE(HttpStatus.PAYLOAD_TOO_LARGE, "파일 용량이 너무 큽니다."),

	// 공통
	VALIDATION_ERROR(HttpStatus.BAD_REQUEST, "요청 값이 올바르지 않습니다."),
	INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "서버 오류가 발생했습니다.");

	private final HttpStatus status;
	private final String message;

	ErrorCode(HttpStatus status, String message) {
		this.status = status;
		this.message = message;
	}

	public HttpStatus getStatus() {
		return status;
	}

	public String getMessage() {
		return message;
	}
}
