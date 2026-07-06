package com.recordapp.domain.feed.controller;

import com.recordapp.domain.diary.dto.DiaryFeedItem;
import com.recordapp.domain.diary.dto.FeedDetailResponse;
import com.recordapp.domain.feed.service.FeedService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.security.SecurityUser;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 피드 API. 컨텍스트 경로(/api/v1) 하위 /feed. 관심사 분리를 위해 DiaryController 와 별도.
 * 본인 식별은 principal 의 userId 로만 수행한다(IDOR 차단). 정적 경로(/feed)와 {@code /{id}}(Long)는 충돌 없음.
 */
@RestController
@RequestMapping("/feed")
public class FeedController {

	private final FeedService feedService;

	public FeedController(FeedService feedService) {
		this.feedService = feedService;
	}

	/** GET /feed?cursor=&size= — 본인+PUBLIC+수락친구 FRIENDS 감정 카드 피드(id DESC 커서). */
	@GetMapping
	public ApiResponse<PageResponse<DiaryFeedItem>> feed(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam(required = false) Long cursor,
			@RequestParam(required = false) Integer size) {
		return ApiResponse.ok(feedService.getFeed(principal.userId(), new CursorRequest(cursor, size)));
	}

	/** GET /feed/{id} — 피드 카드 전문 조회(viewer-aware, 볼 수 없으면 404). */
	@GetMapping("/{id}")
	public ApiResponse<FeedDetailResponse> detail(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		return ApiResponse.ok(feedService.getDetail(principal.userId(), id));
	}
}
