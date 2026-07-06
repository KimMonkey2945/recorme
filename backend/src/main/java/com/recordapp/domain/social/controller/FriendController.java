package com.recordapp.domain.social.controller;

import com.recordapp.domain.social.dto.FriendItem;
import com.recordapp.domain.social.dto.FriendRequestItem;
import com.recordapp.domain.social.dto.FriendRequestResponse;
import com.recordapp.domain.social.dto.FriendSearchItem;
import com.recordapp.domain.social.dto.SendFriendRequest;
import com.recordapp.domain.social.service.FriendService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.security.SecurityUser;
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
 * 친구 API. 컨텍스트 경로(/api/v1) 하위 /friends.
 * 본인 식별은 인증 principal 의 userId 로만, 대상은 친구코드/uuid 로만 지정한다(내부 PK 비노출, IDOR 차단).
 * <p>정적 경로(/search·/requests)와 {@code DELETE /{userUuid}}(String)는 메서드·경로가 달라 충돌하지 않는다.
 */
@RestController
@RequestMapping("/friends")
public class FriendController {

	private final FriendService friendService;

	public FriendController(FriendService friendService) {
		this.friendService = friendService;
	}

	/** POST /friends/requests — 친구 요청(친구코드 또는 uuid). 신규 리소스이므로 201. */
	@PostMapping("/requests")
	public ResponseEntity<ApiResponse<FriendRequestResponse>> request(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestBody SendFriendRequest request) {
		FriendRequestResponse data = friendService.sendRequest(principal.userId(), request);
		return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.ok(data));
	}

	/** POST /friends/requests/{id}/accept — 받은 요청 수락. */
	@PostMapping("/requests/{id}/accept")
	public ApiResponse<Void> accept(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		friendService.accept(principal.userId(), id);
		return ApiResponse.ok();
	}

	/** POST /friends/requests/{id}/reject — 받은 요청 거절. */
	@PostMapping("/requests/{id}/reject")
	public ApiResponse<Void> reject(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		friendService.reject(principal.userId(), id);
		return ApiResponse.ok();
	}

	/**
	 * GET /friends/requests — 친구 요청 목록(커서 페이징). direction="outgoing"=보낸 요청, 그 외=받은 요청.
	 */
	@GetMapping("/requests")
	public ApiResponse<PageResponse<FriendRequestItem>> requests(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam(required = false, defaultValue = "incoming") String direction,
			@RequestParam(required = false) Long cursor,
			@RequestParam(required = false) Integer size) {
		return ApiResponse.ok(
				friendService.getRequests(principal.userId(), direction, new CursorRequest(cursor, size)));
	}

	/** GET /friends — 친구 목록(수락됨, 커서 페이징). */
	@GetMapping
	public ApiResponse<PageResponse<FriendItem>> list(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam(required = false) Long cursor,
			@RequestParam(required = false) Integer size) {
		return ApiResponse.ok(
				friendService.getFriends(principal.userId(), new CursorRequest(cursor, size)));
	}

	/** GET /friends/search?query= — 친구 검색(친구코드 정확 + 닉네임 부분, 상한 20). */
	@GetMapping("/search")
	public ApiResponse<List<FriendSearchItem>> search(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam String query) {
		return ApiResponse.ok(friendService.search(principal.userId(), query));
	}

	/** DELETE /friends/{userUuid}?block= — 친구 삭제(block=false) 또는 차단(block=true). 멱등 200. */
	@DeleteMapping("/{userUuid}")
	public ApiResponse<Void> remove(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable String userUuid,
			@RequestParam(required = false, defaultValue = "false") boolean block) {
		friendService.remove(principal.userId(), userUuid, block);
		return ApiResponse.ok();
	}
}
