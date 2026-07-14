package com.recordapp.domain.character.mapper;

import com.recordapp.domain.character.dto.EquipmentInsertCommand;
import com.recordapp.domain.character.dto.EquippedItemRow;
import com.recordapp.domain.character.dto.UserCharacterStateRow;
import com.recordapp.domain.character.dto.UserProgressRow;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * 사용자별 캐릭터 상태 매퍼 — user_character_state·user_wallets·user_progress·user_item_groups·user_equipment.
 * 모든 조회/수정은 SecurityContext 에서 온 내부 {@code userId} 로만 대상을 좁힌다(IDOR 구조적 차단).
 *
 * <p>기본 상태 3행(state/wallet/progress)은 {@code INSERT … ON CONFLICT DO NOTHING} 으로 JIT 생성한다 —
 * 동시 최초요청 2건이 와도 각 1행(멱등). {@code UserProvisioningService} 와 같은 철학이다.
 */
@Mapper
public interface UserCharacterMapper {

	// ===== JIT 기본 상태(멱등) =====

	/** user_character_state 기본 행(selected_character=NULL, level=1, exp=0). 이미 있으면 0행. */
	int insertStateIfAbsent(@Param("userId") Long userId);

	/** user_wallets 기본 행(balance=0). 이미 있으면 0행. */
	int insertWalletIfAbsent(@Param("userId") Long userId);

	/** user_progress 기본 행(전부 0). 이미 있으면 0행. */
	int insertProgressIfAbsent(@Param("userId") Long userId);

	/**
	 * 기본 지급(acquire_type='DEFAULT') 아이템 그룹 소유 부여. 이미 소유한 그룹은 DO NOTHING(멱등).
	 * 미션 해금·구매는 보상 엔진(Task 028) 소관이고, 여기서는 "가입하면 당연히 갖고 있는" 기본 옷만 심는다.
	 */
	int grantDefaultItemGroups(@Param("userId") Long userId);

	// ===== 조회 =====

	/** 선택 캐릭터·레벨·경험치(행이 없으면 null — 호출 전 JIT 로 보장한다). */
	UserCharacterStateRow findState(@Param("userId") Long userId);

	/** 미션 판정 O(1) 캐시 스냅샷(행이 없으면 null). */
	UserProgressRow findProgress(@Param("userId") Long userId);

	/** 코인 잔액(행이 없으면 null). */
	Integer findWalletBalance(@Param("userId") Long userId);

	/** 미확인 보상 수(character_events.acked_at IS NULL) — 홈 상단 알림 뱃지. */
	int countUnackedRewards(@Param("userId") Long userId);

	/** 소유 중인 group_code 전체(옷장/상점 탭 분기 + 착용 소유 검증). */
	List<String> findOwnedGroupCodes(@Param("userId") Long userId);

	/** 착용 중인 group_code 전체(목록의 equipped 플래그용). */
	List<String> findEquippedGroupCodes(@Param("userId") Long userId);

	/**
	 * ★ 착용 목록 + <b>variant 해석 조인</b>. 착용은 group_code 로만 저장돼 있으므로
	 * (group_code + 선택 캐릭터)로 character_items 를 조인해 image_url/rive_slot/render_meta 를 해석한다.
	 * 캐릭터 전용 variant 를 우선하고 없으면 공용(character_code IS NULL)으로 폴백한다.
	 * 어느 쪽으로도 해석되지 않는 착용 행은 결과에서 빠진다(조회는 조용히 감추고, 착용 시점에 409 로 막는다).
	 *
	 * @param selectedCharacter 선택 캐릭터(미선택이면 null → 공용 variant 만 해석됨)
	 */
	List<EquippedItemRow> findEquippedItems(@Param("userId") Long userId,
			@Param("selectedCharacter") String selectedCharacter);

	// ===== 변경 =====

	/**
	 * 선택 캐릭터 교체. 착용(user_equipment)은 group 단위라 <b>건드리지 않는다</b> —
	 * 다음 조회에서 새 캐릭터 기준으로 variant 만 재해석된다(이것이 옷장이 캐릭터를 따라오는 이유).
	 *
	 * @return 갱신 행 수(0이면 기본 상태 행 부재 — 호출 전 JIT 로 보장)
	 */
	int updateSelectedCharacter(@Param("userId") Long userId,
			@Param("characterCode") String characterCode);

	/** 착용 전체 삭제(배치 교체의 1단계). 같은 트랜잭션에서 INSERT 가 이어진다. */
	int deleteEquipment(@Param("userId") Long userId);

	/** 착용 배치 INSERT(2단계). 검증을 모두 통과한 항목만 온다. 빈 리스트면 호출하지 않는다. */
	int insertEquipment(@Param("userId") Long userId,
			@Param("items") List<EquipmentInsertCommand> items);
}
