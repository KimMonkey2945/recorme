package com.recordapp.domain.social.controller;

import com.recordapp.domain.resolution.dto.ResolutionListItem;
import com.recordapp.domain.social.dto.FriendCharacterResponse;
import com.recordapp.domain.social.dto.FriendDiarySummaryResponse;
import com.recordapp.domain.social.service.FriendBrowseService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.security.SecurityUser;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 친구 둘러보기 API(읽기 전용). 컨텍스트 경로(/api/v1) 하위 /friends/{userUuid}.
 *
 * <p>본인 식별은 principal 의 userId 로만, 대상은 외부 노출 uuid 로만 지정한다(내부 PK 비노출, IDOR 차단).
 * 전부 GET 이며, 친구가 아니면 서비스가 404 로 은닉한다.
 *
 * <p>경로를 반드시 <b>2세그먼트 이상</b>(/character, /diaries/summary …)으로 둔 이유: 단일 세그먼트
 * {@code GET /friends/{userUuid}} 는 기존 정적 경로(/friends/search·/friends/requests)와 형태가 겹쳐
 * 혼동을 부른다. 기존 {@code DELETE /friends/{userUuid}} 와는 메서드·세그먼트 수가 달라 충돌하지 않는다.
 */
@RestController
@RequestMapping("/friends/{userUuid}")
public class FriendBrowseController {

	private final FriendBrowseService friendBrowseService;

	public FriendBrowseController(FriendBrowseService friendBrowseService) {
		this.friendBrowseService = friendBrowseService;
	}

	/** GET /friends/{userUuid}/character — 친구의 캐릭터·착용 아이템(코인·보상 미포함). */
	@GetMapping("/character")
	public ApiResponse<FriendCharacterResponse> character(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable String userUuid) {
		return ApiResponse.ok(friendBrowseService.getCharacter(principal.userId(), userUuid));
	}

	/** GET /friends/{userUuid}/diaries/summary?yearMonth=yyyy-MM — 친구의 캘린더(공개 기록만). */
	@GetMapping("/diaries/summary")
	public ApiResponse<FriendDiarySummaryResponse> diarySummary(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable String userUuid,
			@RequestParam String yearMonth) {
		return ApiResponse.ok(
				friendBrowseService.getDiarySummary(principal.userId(), userUuid, yearMonth));
	}

	/** GET /friends/{userUuid}/resolutions?status=&cursor=&size= — 친구의 작심삼일 목록. */
	@GetMapping("/resolutions")
	public ApiResponse<PageResponse<ResolutionListItem>> resolutions(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable String userUuid,
			@RequestParam(required = false) String status,
			@RequestParam(required = false) Long cursor,
			@RequestParam(required = false) Integer size) {
		return ApiResponse.ok(friendBrowseService.getResolutions(
				principal.userId(), userUuid, status, new CursorRequest(cursor, size)));
	}
}
