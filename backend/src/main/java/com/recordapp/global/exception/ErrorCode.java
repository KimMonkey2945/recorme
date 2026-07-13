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

	// 기록
	DIARY_NOT_FOUND(HttpStatus.NOT_FOUND, "일기를 찾을 수 없습니다."),
	DIARY_ALREADY_CONFIRMED(HttpStatus.CONFLICT, "이미 기억한 일기는 수정할 수 없어요."),
	IMAGE_LIMIT_EXCEEDED(HttpStatus.CONFLICT, "사진은 일기당 최대 5장까지 첨부할 수 있습니다."),

	// 친구(소셜)
	FRIEND_SELF(HttpStatus.BAD_REQUEST, "자기 자신에게는 친구 요청할 수 없어요."),
	FRIEND_ALREADY(HttpStatus.CONFLICT, "이미 친구예요."),
	FRIEND_REQUEST_ALREADY_SENT(HttpStatus.CONFLICT, "이미 보낸 친구 요청이에요."),
	FRIEND_REQUEST_NOT_FOUND(HttpStatus.NOT_FOUND, "친구 요청을 찾을 수 없습니다."),
	FRIEND_BLOCKED(HttpStatus.CONFLICT, "차단된 사용자예요."),

	// 작심삼일(결심)
	RESOLUTION_NOT_FOUND(HttpStatus.NOT_FOUND, "작심삼일을 찾을 수 없습니다."),
	RESOLUTION_NOT_ACTIVE(HttpStatus.CONFLICT, "진행 중인 작심삼일이 아니에요."),
	RESOLUTION_CHECK_NOT_TODAY(HttpStatus.CONFLICT, "오늘 완료할 수 있는 항목이 아니에요."),
	RESOLUTION_NOT_EXTENDABLE(HttpStatus.CONFLICT, "성공한 작심삼일만 연장할 수 있어요."),
	RESOLUTION_ALREADY_EXTENDED(HttpStatus.CONFLICT, "이미 연장한 작심삼일이에요."),

	// 파일 업로드
	INVALID_FILE(HttpStatus.BAD_REQUEST, "허용되지 않는 파일입니다."),
	FILE_TOO_LARGE(HttpStatus.PAYLOAD_TOO_LARGE, "파일 용량이 너무 큽니다."),

	// 공통
	VALIDATION_ERROR(HttpStatus.BAD_REQUEST, "요청 값이 올바르지 않습니다."),
	// 공개 인터넷 노출 대비: 남용/DoS 방어(무인증 엔드포인트·쓰기 경로 rate limit).
	RATE_LIMITED(HttpStatus.TOO_MANY_REQUESTS, "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요."),
	// 감정 분석(LLM) 비용 상한: 사용자별 24시간 확정 횟수 초과.
	DIARY_DAILY_LIMIT(HttpStatus.TOO_MANY_REQUESTS, "오늘 기억할 수 있는 일기 수를 초과했어요. 잠시 후 다시 시도해 주세요."),
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
