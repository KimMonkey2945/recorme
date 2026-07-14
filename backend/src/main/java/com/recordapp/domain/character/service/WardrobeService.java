package com.recordapp.domain.character.service;

import com.recordapp.domain.character.dto.EquipmentInsertCommand;
import com.recordapp.domain.character.dto.EquipmentItemRequest;
import com.recordapp.domain.character.dto.ItemGroupListResponse;
import com.recordapp.domain.character.dto.ItemGroupResponse;
import com.recordapp.domain.character.dto.ItemGroupRow;
import com.recordapp.domain.character.dto.MissionLockResponse;
import com.recordapp.domain.character.dto.MissionResponse;
import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.dto.ResolvedVariant;
import com.recordapp.domain.character.dto.UpdateEquipmentRequest;
import com.recordapp.domain.character.mapper.UserCharacterMapper;
import com.recordapp.domain.character.vo.AcquireType;
import com.recordapp.domain.character.vo.ItemSlot;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 옷장 서비스 — 아이템 목록 조회 + 착용 <b>배치 교체</b>.
 *
 * <p>아이템은 언제나 {@code group_code}(소유·착용 단위)로 다룬다. 캐릭터별 이미지(variant)는 서버가
 * 선택 캐릭터로 해석해 내려주므로 클라이언트는 2단 구조를 알 필요가 없다.
 *
 * <p><b>배치 교체는 원자적이다.</b> 요청 전체를 먼저 검증하고(슬롯 규칙 → 슬롯 일치 → 소유 → variant),
 * 하나라도 실패하면 <b>쓰기 전에</b> 예외를 던진다. 검증을 통과한 경우에만 DELETE→INSERT 를 한
 * 트랜잭션에서 수행한다 — "5개 중 3번째가 미보유면 1·2번도 반영 안 됨"이 자명하게 성립한다.
 * (미소유 착용은 복합 FK 가 최종 방어선이지만, 서비스가 먼저 걸러 SQLException 이 새지 않게 한다.)
 */
@Service
public class WardrobeService {

	private final UserCharacterMapper userCharacterMapper;
	private final CatalogCache catalog;
	private final CharacterService characterService;
	private final MissionService missionService;

	public WardrobeService(UserCharacterMapper userCharacterMapper,
			CatalogCache catalog,
			CharacterService characterService,
			MissionService missionService) {
		this.userCharacterMapper = userCharacterMapper;
		this.catalog = catalog;
		this.characterService = characterService;
		this.missionService = missionService;
	}

	/**
	 * GET /characters/items?slot= — 옷장·상점이 공유하는 단일 목록(slot 생략 시 전체).
	 * owned 로 옷장/상점 탭을 가르고, imageUrl 은 <b>내 캐릭터 기준으로 해석된 variant</b>다.
	 * 내 캐릭터용 variant 가 아직 없는 그룹은 목록에서 제외한다(그릴 수 없는 항목을 노출하지 않는다).
	 */
	@Transactional
	public ItemGroupListResponse getItems(Long userId, String slot) {
		characterService.ensureState(userId);
		ItemSlot filter = (slot == null || slot.isBlank()) ? null : ItemSlot.from(slot);
		String selected = characterService.selectedCharacterOf(userId);

		Set<String> owned = new HashSet<>(userCharacterMapper.findOwnedGroupCodes(userId));
		Set<String> equipped = new HashSet<>(userCharacterMapper.findEquippedGroupCodes(userId));
		Map<String, MissionResponse> missionByRewardGroup = missionsByRewardGroup(userId);

		List<ItemGroupResponse> items = new ArrayList<>();
		for (ItemGroupRow group : catalog.itemGroups()) {
			if (filter != null && group.slot() != filter) {
				continue;
			}
			ResolvedVariant variant = catalog.resolveVariant(group.code(), selected);
			if (variant == null) {
				continue; // 내 캐릭터용 이미지 미제작 → 렌더 불가라 목록에서 제외.
			}
			boolean isOwned = owned.contains(group.code());
			items.add(new ItemGroupResponse(
					group.code(), group.slot(), group.nameKo(), group.thumbnailUrl(),
					group.acquireType(), group.coinPrice(),
					isOwned, equipped.contains(group.code()),
					variant.imageUrl(), variant.renderMeta(),
					lockOf(group, isOwned, missionByRewardGroup)));
		}
		return new ItemGroupListResponse(items);
	}

	/**
	 * PUT /characters/me/equipment — 착용 배치 교체(전체 스냅샷). 빈 배열이면 전 슬롯 비움.
	 * 검증 순서는 고정이다: 슬롯 규칙(400) → 슬롯 일치(400) → 소유(409) → variant(409).
	 */
	@Transactional
	public MyCharacterResponse replaceEquipment(Long userId, UpdateEquipmentRequest request) {
		characterService.ensureState(userId);
		String selected = characterService.selectedCharacterOf(userId);

		List<EquipmentInsertCommand> commands = validate(userId, request.equipment(), selected);

		userCharacterMapper.deleteEquipment(userId);
		if (!commands.isEmpty()) {
			userCharacterMapper.insertEquipment(userId, commands);
		}
		return characterService.buildMyCharacter(userId);
	}

	// ===== 검증 =====

	/** 요청 전체를 검증해 INSERT 커맨드로 변환한다. 하나라도 실패하면 쓰기 전에 예외(→ 전체 롤백). */
	private List<EquipmentInsertCommand> validate(Long userId, List<EquipmentItemRequest> requested,
			String selectedCharacter) {
		Set<String> owned = requested.isEmpty()
				? Set.of()
				: new HashSet<>(userCharacterMapper.findOwnedGroupCodes(userId));

		Set<String> usedPositions = new HashSet<>();   // (slot, slotIndex) 중복 — PK 충돌 선방어
		Set<String> usedGroups = new HashSet<>();      // group 중복 진열 — uq_user_equipment_group 선방어
		List<EquipmentInsertCommand> commands = new ArrayList<>(requested.size());

		for (EquipmentItemRequest item : requested) {
			ItemSlot slot = ItemSlot.from(item.slot());
			short index = item.slotIndex();

			// 1) 슬롯 규칙: 단일 슬롯은 0번 한 칸, ROOM_PROP 만 0~5(DB CHECK 와 동일 규칙을 먼저 400 으로).
			if (index < 0 || index > slot.maxSlotIndex()) {
				throw new BusinessException(ErrorCode.VALIDATION_ERROR,
						slot + " 슬롯의 slotIndex 는 0~" + slot.maxSlotIndex() + " 여야 해요.");
			}
			if (!usedPositions.add(slot.name() + ":" + index)) {
				throw new BusinessException(ErrorCode.VALIDATION_ERROR,
						"같은 칸(" + slot + " " + index + ")에 두 아이템을 착용할 수 없어요.");
			}
			if (!usedGroups.add(item.groupCode())) {
				throw new BusinessException(ErrorCode.VALIDATION_ERROR,
						"같은 아이템(" + item.groupCode() + ")을 두 칸에 진열할 수 없어요.");
			}

			// 2) 그룹 존재 + 슬롯 일치. 미지의 그룹은 소유했을 리 없으므로 ITEM_NOT_OWNED 로 수렴시킨다.
			ItemGroupRow group = catalog.itemGroup(item.groupCode());
			if (group == null) {
				throw new BusinessException(ErrorCode.ITEM_NOT_OWNED,
						"존재하지 않는 아이템이에요: " + item.groupCode());
			}
			if (group.slot() != slot) {
				throw new BusinessException(ErrorCode.ITEM_SLOT_MISMATCH,
						group.nameKo() + "은(는) " + group.slot() + " 부위 아이템이에요.");
			}

			// 3) 소유(복합 FK 가 최종 방어선이지만 서비스가 먼저 409 로 거른다).
			if (!owned.contains(group.code())) {
				throw new BusinessException(ErrorCode.ITEM_NOT_OWNED);
			}

			// 4) 내 캐릭터용 variant 존재(없으면 착용해도 그릴 수 없다).
			if (catalog.resolveVariant(group.code(), selectedCharacter) == null) {
				throw new BusinessException(ErrorCode.ITEM_VARIANT_MISSING,
						group.nameKo() + "의 내 캐릭터용 이미지가 아직 없어요.");
			}

			commands.add(new EquipmentInsertCommand(slot.name(), index, group.code()));
		}
		return commands;
	}

	// ===== 내부 =====

	/** 미션 해금 아이템의 잠금 정보(미보유 + MISSION 일 때만). 그 외에는 null. */
	private MissionLockResponse lockOf(ItemGroupRow group, boolean owned,
			Map<String, MissionResponse> missionByRewardGroup) {
		if (owned || group.acquireType() != AcquireType.MISSION) {
			return null;
		}
		MissionResponse mission = missionByRewardGroup.get(group.code());
		if (mission == null) {
			return null;
		}
		return new MissionLockResponse(mission.code(), mission.title(), mission.progress(), mission.threshold());
	}

	/** 아이템 그룹 → 그 그룹을 보상으로 주는 미션(진행률 포함). 미션 목록 1회 산출로 lockedBy 를 전부 채운다. */
	private Map<String, MissionResponse> missionsByRewardGroup(Long userId) {
		Map<String, MissionResponse> byGroup = new HashMap<>();
		for (MissionResponse mission : missionService.buildMissions(userId)) {
			if (mission.itemGroupReward() != null) {
				byGroup.putIfAbsent(mission.itemGroupReward(), mission);
			}
		}
		return byGroup;
	}
}
