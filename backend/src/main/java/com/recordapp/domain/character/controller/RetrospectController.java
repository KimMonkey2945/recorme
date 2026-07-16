package com.recordapp.domain.character.controller;

import com.recordapp.domain.character.dto.RetrospectResponse;
import com.recordapp.domain.character.service.RetrospectService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SecurityUser;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 월간 회고 API(Task 032 — 락인). 컨텍스트 경로(/api/v1) 하위 /characters.
 * 본인 식별은 인증 principal 의 userId 로만 수행한다(경로·바디에 사용자 식별자 없음 — IDOR 차단).
 */
@RestController
@RequestMapping("/characters")
public class RetrospectController {

	private final RetrospectService retrospectService;

	public RetrospectController(RetrospectService retrospectService) {
		this.retrospectService = retrospectService;
	}

	/**
	 * GET /characters/me/retrospect?yearMonth=YYYY-MM — 이달의 기록·연속일·감정 분포·획득 코인·획득 아이템.
	 * yearMonth 형식이 잘못되면 400 VALIDATION_ERROR. 기록이 없는 달도 빈 집계로 정상 응답한다.
	 */
	@GetMapping("/me/retrospect")
	public ApiResponse<RetrospectResponse> getRetrospect(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam String yearMonth) {
		return ApiResponse.ok(retrospectService.getRetrospect(principal.userId(), parseYearMonth(yearMonth)));
	}

	/** YYYY-MM 파싱(실패 시 400). YearMonth 는 "2026-07" 형식만 받는다. */
	private YearMonth parseYearMonth(String raw) {
		try {
			return YearMonth.parse(raw);
		} catch (DateTimeParseException e) {
			throw new BusinessException(ErrorCode.VALIDATION_ERROR, "yearMonth 형식이 올바르지 않아요(YYYY-MM).");
		}
	}
}
