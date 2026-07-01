package com.recordapp.domain.resolution.controller;

import com.recordapp.domain.resolution.dto.CreateResolutionRequest;
import com.recordapp.domain.resolution.dto.ExtendResolutionRequest;
import com.recordapp.domain.resolution.dto.ResolutionCalendarDay;
import com.recordapp.domain.resolution.dto.ResolutionDetailResponse;
import com.recordapp.domain.resolution.dto.ResolutionListItem;
import com.recordapp.domain.resolution.service.ResolutionService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.security.SecurityUser;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 작심삼일 API. 컨텍스트 경로(/api/v1) 하위 /resolutions.
 * 본인 식별은 인증 principal 의 userId 로만 수행한다(요청 바디·경로에 사용자 식별자 없음, IDOR 차단).
 * <p>생성/연장은 신규 리소스를 만들어 201 을 반환하므로 {@link ResponseEntity}로 상태코드를 분기한다
 * (DiaryController 의 201 분기 관례). 정적 경로(/me·/me/calendar)는 {@code /{id}}(Long)와 타입이 달라 충돌하지 않는다.
 */
@RestController
@RequestMapping("/resolutions")
public class ResolutionController {

	private final ResolutionService resolutionService;

	public ResolutionController(ResolutionService resolutionService) {
		this.resolutionService = resolutionService;
	}

	/** POST /resolutions — 작심삼일 생성. 신규 리소스이므로 201. */
	@PostMapping
	public ResponseEntity<ApiResponse<ResolutionDetailResponse>> create(
			@AuthenticationPrincipal SecurityUser principal,
			@Valid @RequestBody CreateResolutionRequest request) {
		ResolutionDetailResponse data = resolutionService.create(principal.userId(), request);
		return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.ok(data));
	}

	/**
	 * GET /resolutions/me — 내 결심 목록(커서 페이징, id DESC).
	 * status(ONGOING/SUCCESS/FAILED) 필터는 optional. cursor 생략 시 첫 페이지, size 기본 20·최대 50.
	 */
	@GetMapping("/me")
	public ApiResponse<PageResponse<ResolutionListItem>> getMyList(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam(required = false) String status,
			@RequestParam(required = false) Long cursor,
			@RequestParam(required = false) Integer size) {
		return ApiResponse.ok(
				resolutionService.getList(principal.userId(), status, new CursorRequest(cursor, size)));
	}

	/** GET /resolutions/me/calendar — 월별 캘린더((날짜, 결심)당 1행). yearMonth="yyyy-MM". */
	@GetMapping("/me/calendar")
	public ApiResponse<List<ResolutionCalendarDay>> getCalendar(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam String yearMonth) {
		return ApiResponse.ok(resolutionService.getCalendar(principal.userId(), yearMonth));
	}

	/** GET /resolutions/{id} — 결심 단건 상세(헤더 + 3일 체크). */
	@GetMapping("/{id}")
	public ApiResponse<ResolutionDetailResponse> getById(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		return ApiResponse.ok(resolutionService.getDetail(principal.userId(), id));
	}

	/** POST /resolutions/{id}/checks/today — 오늘자 완료 체크(멱등). */
	@PostMapping("/{id}/checks/today")
	public ApiResponse<ResolutionDetailResponse> completeToday(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		return ApiResponse.ok(resolutionService.completeToday(principal.userId(), id));
	}

	/** POST /resolutions/{id}/extend — 성공한 결심을 '다음 3일'로 연장(같은 streak_group). 신규 리소스이므로 201. */
	@PostMapping("/{id}/extend")
	public ResponseEntity<ApiResponse<ResolutionDetailResponse>> extend(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id,
			@RequestBody ExtendResolutionRequest request) {
		ResolutionDetailResponse data = resolutionService.extend(principal.userId(), id, request);
		return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.ok(data));
	}

	/** DELETE /resolutions/{id} — 결심 취소(소프트 삭제). */
	@DeleteMapping("/{id}")
	public ApiResponse<Void> delete(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		resolutionService.cancel(principal.userId(), id);
		return ApiResponse.ok();
	}
}
