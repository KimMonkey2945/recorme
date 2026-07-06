package com.recordapp.domain.social.controller;

import com.recordapp.domain.social.dto.ReactionResponse;
import com.recordapp.domain.social.service.ReactionService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.security.SecurityUser;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 공감(리액션) API. URL 은 diary 자원(/diaries/{id}/reactions)이나 코드는 social 도메인에 둔다
 * (소셜 상호작용 응집). 본인 식별은 principal.userId 로만(IDOR 차단). 댓글은 범위 외.
 * <p>정적 하위 경로(/{id}/reactions)라 DiaryController 의 /{id}·/{id}/visibility 와 충돌하지 않는다.
 */
@RestController
@RequestMapping("/diaries/{id}/reactions")
public class ReactionController {

	private final ReactionService reactionService;

	public ReactionController(ReactionService reactionService) {
		this.reactionService = reactionService;
	}

	/** POST /diaries/{id}/reactions — 공감 추가(멱등 200). 볼 수 없는 글이면 404. */
	@PostMapping
	public ApiResponse<ReactionResponse> add(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		return ApiResponse.ok(reactionService.react(principal.userId(), id));
	}

	/** DELETE /diaries/{id}/reactions — 공감 취소(멱등 200). */
	@DeleteMapping
	public ApiResponse<ReactionResponse> remove(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		return ApiResponse.ok(reactionService.cancel(principal.userId(), id));
	}
}
