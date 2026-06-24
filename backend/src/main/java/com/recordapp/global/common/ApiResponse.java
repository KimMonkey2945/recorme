package com.recordapp.global.common;

import com.recordapp.global.exception.ErrorCode;

/**
 * 표준 API 응답 래퍼.
 * 성공: { "success": true,  "data": {...}, "error": null }
 * 실패: { "success": false, "data": null,  "error": { "code": "...", "message": "..." } }
 */
public record ApiResponse<T>(boolean success, T data, ApiError error) {

	public static <T> ApiResponse<T> ok(T data) {
		return new ApiResponse<>(true, data, null);
	}

	public static ApiResponse<Void> ok() {
		return new ApiResponse<>(true, null, null);
	}

	public static ApiResponse<Void> fail(ErrorCode code) {
		return new ApiResponse<>(false, null, new ApiError(code.name(), code.getMessage()));
	}

	/** 동일 코드에 상황별 상세 메시지를 덧붙일 때 사용 */
	public static ApiResponse<Void> fail(ErrorCode code, String message) {
		return new ApiResponse<>(false, null, new ApiError(code.name(), message));
	}

	public record ApiError(String code, String message) {
	}
}
