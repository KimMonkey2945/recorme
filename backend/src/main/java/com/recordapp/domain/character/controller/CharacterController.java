package com.recordapp.domain.character.controller;

import com.recordapp.domain.character.dto.CharacterListResponse;
import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.dto.SelectCharacterRequest;
import com.recordapp.domain.character.service.CharacterService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.security.SecurityUser;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 캐릭터 API. 컨텍스트 경로(/api/v1) 하위 /characters.
 * 본인 식별은 인증 principal 의 userId 로만 수행한다(경로·바디에 사용자 식별자 없음 — IDOR 차단).
 * 아이템·착용은 {@link WardrobeController}, 미션은 {@link MissionController} 소관이다.
 */
@RestController
@RequestMapping("/characters")
public class CharacterController {

	private final CharacterService characterService;

	public CharacterController(CharacterService characterService) {
		this.characterService = characterService;
	}

	/** GET /characters — 선택 가능한 캐릭터 목록 + 보유·선택 여부(온보딩 캐러셀·교체 화면). */
	@GetMapping
	public ApiResponse<CharacterListResponse> getCharacters(
			@AuthenticationPrincipal SecurityUser principal) {
		return ApiResponse.ok(characterService.getCharacters(principal.userId()));
	}

	/**
	 * GET /characters/me — 내 캐릭터 상태(선택·착용·레벨/경험치·코인·미확인 보상 수).
	 * ★ 캐릭터 미선택(신규 가입 직후)이어도 200 + {@code character: null} 이다 — 앱이 이 null 로 온보딩을 띄운다.
	 */
	@GetMapping("/me")
	public ApiResponse<MyCharacterResponse> getMyCharacter(
			@AuthenticationPrincipal SecurityUser principal) {
		return ApiResponse.ok(characterService.getMyCharacter(principal.userId()));
	}

	/** PUT /characters/me/selection — 캐릭터 선택/교체(착용 유지 + variant 재해석). 응답은 갱신된 내 캐릭터. */
	@PutMapping("/me/selection")
	public ApiResponse<MyCharacterResponse> selectCharacter(
			@AuthenticationPrincipal SecurityUser principal,
			@Valid @RequestBody SelectCharacterRequest request) {
		return ApiResponse.ok(characterService.selectCharacter(principal.userId(), request));
	}
}
