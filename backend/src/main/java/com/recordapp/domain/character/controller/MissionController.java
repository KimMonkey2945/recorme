package com.recordapp.domain.character.controller;

import com.recordapp.domain.character.dto.MissionListResponse;
import com.recordapp.domain.character.service.MissionService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.security.SecurityUser;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 미션 API. 컨텍스트 경로(/api/v1) 하위 /missions.
 * 해금의 유일한 경로이며, 판정·지급은 보상 엔진(Task 028)이 수행한다 — 여기서는 조회만 한다.
 */
@RestController
@RequestMapping("/missions")
public class MissionController {

	private final MissionService missionService;

	public MissionController(MissionService missionService) {
		this.missionService = missionService;
	}

	/** GET /missions — 미션 목록 + 달성 여부 + 진행률(user_progress 기반 O(1)). */
	@GetMapping
	public ApiResponse<MissionListResponse> getMissions(
			@AuthenticationPrincipal SecurityUser principal) {
		return ApiResponse.ok(missionService.getMissions(principal.userId()));
	}
}
