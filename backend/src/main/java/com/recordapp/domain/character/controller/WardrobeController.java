package com.recordapp.domain.character.controller;

import com.recordapp.domain.character.dto.ItemGroupListResponse;
import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.dto.UpdateEquipmentRequest;
import com.recordapp.domain.character.service.WardrobeService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.security.SecurityUser;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 옷장·상점 API(아이템 목록 + 착용 배치 교체). /characters 하위이지만 관심사가 달라 컨트롤러를 분리한다.
 * 정적 경로(/items·/me/equipment)라 {@link CharacterController} 의 매핑과 충돌하지 않는다.
 * 구매(POST /characters/items/{groupCode}/purchase)는 보상 엔진(Task 028) 소관이다.
 */
@RestController
@RequestMapping("/characters")
public class WardrobeController {

	private final WardrobeService wardrobeService;

	public WardrobeController(WardrobeService wardrobeService) {
		this.wardrobeService = wardrobeService;
	}

	/**
	 * GET /characters/items?slot= — 아이템 그룹 목록(슬롯 필터, 생략 시 전체).
	 * owned 로 옷장/상점 탭을 가르고, imageUrl 은 내 캐릭터 기준으로 해석된 variant 다.
	 */
	@GetMapping("/items")
	public ApiResponse<ItemGroupListResponse> getItems(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam(required = false) String slot) {
		return ApiResponse.ok(wardrobeService.getItems(principal.userId(), slot));
	}

	/**
	 * PUT /characters/me/equipment — 착용 배치 교체(보낸 배열이 착용 전체 스냅샷). 빈 배열이면 전 슬롯 비움.
	 * 일부라도 검증에 실패하면 전체 롤백(원자적). 응답은 갱신된 내 캐릭터.
	 */
	@PutMapping("/me/equipment")
	public ApiResponse<MyCharacterResponse> replaceEquipment(
			@AuthenticationPrincipal SecurityUser principal,
			@Valid @RequestBody UpdateEquipmentRequest request) {
		return ApiResponse.ok(wardrobeService.replaceEquipment(principal.userId(), request));
	}
}
