package com.recordapp.domain.character;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.domain.character.controller.CharacterController;
import com.recordapp.domain.character.controller.MissionController;
import com.recordapp.domain.character.controller.WardrobeController;
import com.recordapp.domain.character.dto.CharacterListResponse;
import com.recordapp.domain.character.dto.CharacterResponse;
import com.recordapp.domain.character.dto.EquippedItemResponse;
import com.recordapp.domain.character.dto.ItemGroupListResponse;
import com.recordapp.domain.character.dto.ItemGroupResponse;
import com.recordapp.domain.character.dto.MissionListResponse;
import com.recordapp.domain.character.dto.MissionResponse;
import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.dto.SelectCharacterRequest;
import com.recordapp.domain.character.dto.SelectedCharacterResponse;
import com.recordapp.domain.character.dto.UpdateEquipmentRequest;
import com.recordapp.domain.character.service.CharacterService;
import com.recordapp.domain.character.service.MissionService;
import com.recordapp.domain.character.service.WardrobeService;
import com.recordapp.domain.character.vo.AcquireType;
import com.recordapp.domain.character.vo.ItemSlot;
import com.recordapp.domain.character.vo.MissionRuleType;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.JwtAuthenticationEntryPoint;
import com.recordapp.global.security.SecurityConfig;
import com.recordapp.global.security.SupabaseJwtFilter;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.autoconfigure.security.servlet.SecurityFilterAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.FilterType;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 캐릭터·옷장·미션 컨트롤러 슬라이스 테스트(Docker 불필요 — DiaryControllerTest 관례).
 *
 * <p>보안 필터 체인은 슬라이스에서 제외하고, ① 요청 바디 검증(400) ② 표준 응답 래핑
 * ③ BusinessException → ErrorCode(HTTP 상태·code) 매핑 ④ 앱(Task 029)이 의존하는 필드명
 * (특히 캐릭터 미선택 시 {@code character: null})을 검증한다.
 * DB 를 타는 정상 경로·소유권·variant 재해석은 {@link CharacterServiceTest}(Testcontainers)가 검증한다.
 */
@WebMvcTest(controllers = {CharacterController.class, WardrobeController.class, MissionController.class},
		excludeFilters = @ComponentScan.Filter(
				type = FilterType.ASSIGNABLE_TYPE,
				classes = {SecurityConfig.class, SupabaseJwtFilter.class, JwtAuthenticationEntryPoint.class}),
		excludeAutoConfiguration = {SecurityAutoConfiguration.class, SecurityFilterAutoConfiguration.class})
@AutoConfigureMockMvc(addFilters = false)
class CharacterControllerTest {

	@Autowired
	MockMvc mockMvc;

	@Autowired
	ObjectMapper objectMapper;

	@MockitoBean
	CharacterService characterService;

	@MockitoBean
	WardrobeService wardrobeService;

	@MockitoBean
	MissionService missionService;

	// ===== 픽스처 =====

	/** 캐릭터 미선택 상태(신규 가입 직후) — character=null, 기본값. */
	private MyCharacterResponse unselected() {
		return new MyCharacterResponse(null, 1, 0, 100, 0, 0, List.of());
	}

	/** MONKEY 선택 + 후드티(OUTFIT) 착용 상태. */
	private MyCharacterResponse monkeyWithHoodie() {
		return new MyCharacterResponse(
				new SelectedCharacterResponse("MONKEY", "원숭이", "monkey", "assets/characters/monkey.png"),
				3, 40, 100, 120, 2,
				List.of(new EquippedItemResponse("OUTFIT", (short) 0, "OUTFIT_BASIC_TEE", "기본 흰 티셔츠",
						"assets/items/outfit_basic_tee_monkey.png", "outfit",
						objectMapper.createObjectNode().put("scale", 0.6))));
	}

	// ===== GET /characters =====

	@Test
	void getCharacters_returnsOnboardingFields() throws Exception {
		// 온보딩 캐러셀이 쓰는 필드(code·nameKo·tagline·thumbnailUrl·selected)가 계약대로 나오는지.
		when(characterService.getCharacters(any())).thenReturn(new CharacterListResponse(null, List.of(
				new CharacterResponse("MONKEY", "원숭이", "느긋한 친구",
						"assets/characters/monkey.png", true, false),
				new CharacterResponse("RED_PANDA", "레서판다", "부지런한 친구",
						"assets/characters/red_panda.png", true, false))));

		mockMvc.perform(get("/characters"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.selectedCharacter").doesNotExist()) // 미선택 → null
				.andExpect(jsonPath("$.data.items.length()").value(2))
				.andExpect(jsonPath("$.data.items[0].code").value("MONKEY"))
				.andExpect(jsonPath("$.data.items[0].nameKo").value("원숭이"))
				.andExpect(jsonPath("$.data.items[0].tagline").value("느긋한 친구"))
				.andExpect(jsonPath("$.data.items[0].thumbnailUrl").value("assets/characters/monkey.png"))
				.andExpect(jsonPath("$.data.items[0].owned").value(true))
				.andExpect(jsonPath("$.data.items[0].selected").value(false))
				.andExpect(jsonPath("$.data.items[1].code").value("RED_PANDA"));
	}

	// ===== GET /characters/me =====

	@Test
	void getMyCharacter_unselected_returns200WithNullCharacter() throws Exception {
		// ★ 신규 가입자(캐릭터 미선택)에게도 404 가 아니라 200 + character:null — 앱의 온보딩 리다이렉트 신호.
		when(characterService.getMyCharacter(any())).thenReturn(unselected());

		mockMvc.perform(get("/characters/me"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.success").value(true))
				.andExpect(jsonPath("$.data.character").doesNotExist())
				.andExpect(jsonPath("$.data.level").value(1))
				.andExpect(jsonPath("$.data.exp").value(0))
				.andExpect(jsonPath("$.data.expToNext").value(100))
				.andExpect(jsonPath("$.data.coinBalance").value(0))
				.andExpect(jsonPath("$.data.unackedRewardCount").value(0))
				.andExpect(jsonPath("$.data.equipment").isArray())
				.andExpect(jsonPath("$.data.equipment.length()").value(0));
	}

	@Test
	void getMyCharacter_selected_returnsResolvedEquipment() throws Exception {
		when(characterService.getMyCharacter(any())).thenReturn(monkeyWithHoodie());

		mockMvc.perform(get("/characters/me"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.character.code").value("MONKEY"))
				.andExpect(jsonPath("$.data.character.riveArtboard").value("monkey"))
				.andExpect(jsonPath("$.data.level").value(3))
				.andExpect(jsonPath("$.data.coinBalance").value(120))
				.andExpect(jsonPath("$.data.unackedRewardCount").value(2))
				.andExpect(jsonPath("$.data.equipment[0].slot").value("OUTFIT"))
				.andExpect(jsonPath("$.data.equipment[0].slotIndex").value(0))
				.andExpect(jsonPath("$.data.equipment[0].groupCode").value("OUTFIT_BASIC_TEE"))
				// imageUrl 은 선택 캐릭터(MONKEY) 기준으로 해석된 variant
				.andExpect(jsonPath("$.data.equipment[0].imageUrl")
						.value("assets/items/outfit_basic_tee_monkey.png"))
				.andExpect(jsonPath("$.data.equipment[0].riveSlot").value("outfit"))
				.andExpect(jsonPath("$.data.equipment[0].renderMeta.scale").value(0.6));
	}

	// ===== PUT /characters/me/selection =====

	@Test
	void selectCharacter_valid_returns200AndBindsCode() throws Exception {
		when(characterService.selectCharacter(any(), any(SelectCharacterRequest.class)))
				.thenReturn(monkeyWithHoodie());

		mockMvc.perform(put("/characters/me/selection")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"characterCode\":\"MONKEY\"}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.character.code").value("MONKEY"));

		ArgumentCaptor<SelectCharacterRequest> captor = ArgumentCaptor.forClass(SelectCharacterRequest.class);
		verify(characterService).selectCharacter(any(), captor.capture());
		assertThat(captor.getValue().characterCode()).isEqualTo("MONKEY");
	}

	@Test
	void selectCharacter_blankCode_returns400() throws Exception {
		mockMvc.perform(put("/characters/me/selection")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"characterCode\":\"\"}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(characterService);
	}

	@Test
	void selectCharacter_unknownCode_returns409() throws Exception {
		// 없는/비활성 캐릭터 → 409 CHARACTER_NOT_OWNED.
		when(characterService.selectCharacter(any(), any(SelectCharacterRequest.class)))
				.thenThrow(new BusinessException(ErrorCode.CHARACTER_NOT_OWNED));

		mockMvc.perform(put("/characters/me/selection")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"characterCode\":\"CAT\"}"))
				.andExpect(status().isConflict())
				.andExpect(jsonPath("$.success").value(false))
				.andExpect(jsonPath("$.error.code").value("CHARACTER_NOT_OWNED"));
	}

	// ===== PUT /characters/me/equipment =====

	@Test
	void replaceEquipment_valid_returns200AndBindsBatch() throws Exception {
		when(wardrobeService.replaceEquipment(any(), any(UpdateEquipmentRequest.class)))
				.thenReturn(monkeyWithHoodie());

		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"equipment\":["
								+ "{\"slot\":\"OUTFIT\",\"slotIndex\":0,\"groupCode\":\"OUTFIT_BASIC_TEE\"},"
								+ "{\"slot\":\"ROOM_PROP\",\"slotIndex\":3,\"groupCode\":\"ROOM_PROP_PLANT\"}]}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.equipment[0].groupCode").value("OUTFIT_BASIC_TEE"));

		ArgumentCaptor<UpdateEquipmentRequest> captor = ArgumentCaptor.forClass(UpdateEquipmentRequest.class);
		verify(wardrobeService).replaceEquipment(any(), captor.capture());
		assertThat(captor.getValue().equipment()).hasSize(2);
		assertThat(captor.getValue().equipment().get(1).slot()).isEqualTo("ROOM_PROP");
		assertThat(captor.getValue().equipment().get(1).slotIndex()).isEqualTo((short) 3);
	}

	@Test
	void replaceEquipment_emptyBatch_isAllowed() throws Exception {
		// 빈 배열 = 전 슬롯 해제(별도 DELETE 엔드포인트 없음).
		when(wardrobeService.replaceEquipment(any(), any(UpdateEquipmentRequest.class)))
				.thenReturn(unselected());

		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"equipment\":[]}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.equipment.length()").value(0));
	}

	@Test
	void replaceEquipment_slotIndexOutOfRange_returns400() throws Exception {
		// slotIndex=6 → @Max(5) 위반(ROOM_PROP 도 0~5). 서비스 미호출.
		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"equipment\":[{\"slot\":\"ROOM_PROP\",\"slotIndex\":6,"
								+ "\"groupCode\":\"ROOM_PROP_PLANT\"}]}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(wardrobeService);
	}

	@Test
	void replaceEquipment_blankGroupCode_returns400() throws Exception {
		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"equipment\":[{\"slot\":\"HAT\",\"slotIndex\":0,\"groupCode\":\"\"}]}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(wardrobeService);
	}

	@Test
	void replaceEquipment_missingEquipmentField_returns400() throws Exception {
		// equipment(@NotNull) 누락 → 400(전체 스냅샷 PUT 이므로 "빈 배열"과 "누락"은 다르다).
		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		verifyNoInteractions(wardrobeService);
	}

	@Test
	void replaceEquipment_notOwned_returns409() throws Exception {
		when(wardrobeService.replaceEquipment(any(), any(UpdateEquipmentRequest.class)))
				.thenThrow(new BusinessException(ErrorCode.ITEM_NOT_OWNED));

		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"equipment\":[{\"slot\":\"HAT\",\"slotIndex\":0,"
								+ "\"groupCode\":\"HAT_STRAW\"}]}"))
				.andExpect(status().isConflict())
				.andExpect(jsonPath("$.error.code").value("ITEM_NOT_OWNED"));
	}

	@Test
	void replaceEquipment_slotMismatch_returns400() throws Exception {
		when(wardrobeService.replaceEquipment(any(), any(UpdateEquipmentRequest.class)))
				.thenThrow(new BusinessException(ErrorCode.ITEM_SLOT_MISMATCH));

		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"equipment\":[{\"slot\":\"HAT\",\"slotIndex\":0,"
								+ "\"groupCode\":\"OUTFIT_BASIC_TEE\"}]}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("ITEM_SLOT_MISMATCH"));
	}

	@Test
	void replaceEquipment_variantMissing_returns409() throws Exception {
		when(wardrobeService.replaceEquipment(any(), any(UpdateEquipmentRequest.class)))
				.thenThrow(new BusinessException(ErrorCode.ITEM_VARIANT_MISSING));

		mockMvc.perform(put("/characters/me/equipment")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"equipment\":[{\"slot\":\"HAT\",\"slotIndex\":0,"
								+ "\"groupCode\":\"HAT_PARTY\"}]}"))
				.andExpect(status().isConflict())
				.andExpect(jsonPath("$.error.code").value("ITEM_VARIANT_MISSING"));
	}

	// ===== GET /characters/items =====

	@Test
	void getItems_passesSlotFilter_andReturnsVariantImage() throws Exception {
		when(wardrobeService.getItems(any(), eq("HAT"))).thenReturn(new ItemGroupListResponse(List.of(
				new ItemGroupResponse("HAT_PARTY", ItemSlot.HAT, "파티 모자", "assets/items/hat_party.png",
						AcquireType.MISSION, 0, false, false,
						"assets/items/hat_party_monkey.png",
						objectMapper.createObjectNode().put("z", 40),
						new com.recordapp.domain.character.dto.MissionLockResponse(
								"DIARY_10", "기록 10개", 6, 10)))));

		mockMvc.perform(get("/characters/items").param("slot", "HAT"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.items[0].groupCode").value("HAT_PARTY"))
				.andExpect(jsonPath("$.data.items[0].slot").value("HAT"))
				.andExpect(jsonPath("$.data.items[0].acquireType").value("MISSION"))
				.andExpect(jsonPath("$.data.items[0].owned").value(false))
				.andExpect(jsonPath("$.data.items[0].equipped").value(false))
				.andExpect(jsonPath("$.data.items[0].imageUrl")
						.value("assets/items/hat_party_monkey.png"))
				.andExpect(jsonPath("$.data.items[0].renderMeta.z").value(40))
				.andExpect(jsonPath("$.data.items[0].lockedBy.missionCode").value("DIARY_10"))
				.andExpect(jsonPath("$.data.items[0].lockedBy.progress").value(6))
				.andExpect(jsonPath("$.data.items[0].lockedBy.threshold").value(10));

		verify(wardrobeService).getItems(any(), eq("HAT"));
	}

	@Test
	void getItems_withoutSlot_passesNull() throws Exception {
		when(wardrobeService.getItems(any(), Mockito.isNull()))
				.thenReturn(new ItemGroupListResponse(List.of()));

		mockMvc.perform(get("/characters/items"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.items.length()").value(0));

		verify(wardrobeService).getItems(any(), Mockito.isNull());
	}

	// ===== GET /missions =====

	@Test
	void getMissions_returnsProgressAndAchievement() throws Exception {
		when(missionService.getMissions(any())).thenReturn(new MissionListResponse(List.of(
				new MissionResponse("DIARY_10", "기록 10개", "기록을 10개 확정하면 파티 모자를 드려요.",
						new MissionResponse.Rule(MissionRuleType.DIARY_COUNT, 10),
						7, 10, false, null, 50, "HAT_PARTY"))));

		mockMvc.perform(get("/missions"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.items[0].code").value("DIARY_10"))
				.andExpect(jsonPath("$.data.items[0].rule.type").value("DIARY_COUNT"))
				.andExpect(jsonPath("$.data.items[0].rule.threshold").value(10))
				.andExpect(jsonPath("$.data.items[0].progress").value(7))   // 10개 중 7개 → 70%
				.andExpect(jsonPath("$.data.items[0].threshold").value(10))
				.andExpect(jsonPath("$.data.items[0].achieved").value(false))
				.andExpect(jsonPath("$.data.items[0].achievedAt").doesNotExist())
				.andExpect(jsonPath("$.data.items[0].coinReward").value(50))
				.andExpect(jsonPath("$.data.items[0].itemGroupReward").value("HAT_PARTY"));
	}
}
