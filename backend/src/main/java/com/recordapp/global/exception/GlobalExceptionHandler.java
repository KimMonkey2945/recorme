package com.recordapp.global.exception;

import com.recordapp.global.common.ApiResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;

/**
 * 전역 예외 핸들러. 모든 예외를 표준 응답 포맷으로 변환한다.
 * 예상치 못한 예외는 500 + INTERNAL_ERROR로 마스킹(상세 메시지 비노출).
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

	private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

	@ExceptionHandler(BusinessException.class)
	public ResponseEntity<ApiResponse<Void>> handleBusiness(BusinessException e) {
		ErrorCode code = e.getErrorCode();
		return ResponseEntity.status(code.getStatus()).body(ApiResponse.fail(code, e.getMessage()));
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	public ResponseEntity<ApiResponse<Void>> handleValidation(MethodArgumentNotValidException e) {
		FieldError fieldError = e.getBindingResult().getFieldError();
		String message = fieldError != null
				? fieldError.getField() + ": " + fieldError.getDefaultMessage()
				: ErrorCode.VALIDATION_ERROR.getMessage();
		return ResponseEntity.status(ErrorCode.VALIDATION_ERROR.getStatus())
				.body(ApiResponse.fail(ErrorCode.VALIDATION_ERROR, message));
	}

	@ExceptionHandler(MaxUploadSizeExceededException.class)
	public ResponseEntity<ApiResponse<Void>> handleMaxUpload(MaxUploadSizeExceededException e) {
		return ResponseEntity.status(ErrorCode.FILE_TOO_LARGE.getStatus())
				.body(ApiResponse.fail(ErrorCode.FILE_TOO_LARGE));
	}

	/** 멀티파트 필수 파트 누락(예: avatar 업로드에서 file 파트 미포함)을 400으로 변환(기본 catch-all의 500 방지). */
	@ExceptionHandler(MissingServletRequestPartException.class)
	public ResponseEntity<ApiResponse<Void>> handleMissingPart(MissingServletRequestPartException e) {
		String message = "'" + e.getRequestPartName() + "' 파트가 요청에 없습니다.";
		return ResponseEntity.status(ErrorCode.VALIDATION_ERROR.getStatus())
				.body(ApiResponse.fail(ErrorCode.VALIDATION_ERROR, message));
	}

	@ExceptionHandler(Exception.class)
	public ResponseEntity<ApiResponse<Void>> handleUnexpected(Exception e) {
		log.error("처리되지 않은 예외", e);
		return ResponseEntity.status(ErrorCode.INTERNAL_ERROR.getStatus())
				.body(ApiResponse.fail(ErrorCode.INTERNAL_ERROR));
	}
}
