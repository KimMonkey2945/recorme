package com.recordapp.domain.character.service;

import com.recordapp.domain.character.CharacterConstants;
import com.recordapp.domain.character.dto.CharacterListResponse;
import com.recordapp.domain.character.dto.CharacterResponse;
import com.recordapp.domain.character.dto.CharacterRow;
import com.recordapp.domain.character.dto.EquippedItemResponse;
import com.recordapp.domain.character.dto.EquippedItemRow;
import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.dto.SelectCharacterRequest;
import com.recordapp.domain.character.dto.SelectedCharacterResponse;
import com.recordapp.domain.character.dto.UserCharacterStateRow;
import com.recordapp.domain.character.mapper.UserCharacterMapper;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.util.List;
import java.util.Objects;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 캐릭터 조회·선택 서비스. 소유권은 SecurityContext 의 내부 userId 로만 식별한다(IDOR 구조적 차단 —
 * 경로·바디에 사용자 식별자가 없다).
 *
 * <p><b>기본 상태 JIT</b>: 캐릭터 도메인의 모든 진입점은 {@link #ensureState(Long)} 를 먼저 통과한다.
 * user_character_state/user_wallets/user_progress 3행 + 기본 지급 아이템 소유를 ON CONFLICT DO NOTHING
 * 으로 심으므로 <b>멱등</b>하다(동시 2회 호출에도 각 1행). UserProvisioningService 와 같은 철학이다.
 *
 * <p><b>캐릭터 교체 = 착용 유지 + variant 재해석</b>: 소유·착용은 group_code 단위로만 저장돼 있어
 * selected_character 만 갈아끼우면 다음 조회에서 image_url/render_meta 가 새 캐릭터 기준으로 재해석된다.
 * 옷장이 캐릭터를 따라오는 이유이자 이 도메인의 핵심 불변식이다.
 */
@Service
public class CharacterService {

	private final UserCharacterMapper userCharacterMapper;
	private final CatalogCache catalog;

	public CharacterService(UserCharacterMapper userCharacterMapper, CatalogCache catalog) {
		this.userCharacterMapper = userCharacterMapper;
		this.catalog = catalog;
	}

	/**
	 * 기본 상태 JIT 생성(멱등). 상태 3행 + 기본 지급(DEFAULT) 아이템 소유.
	 * 캐릭터 도메인 진입점(조회 포함)에서 항상 먼저 호출한다 — 신규 가입자도 빈 화면 대신 정상 응답을 받는다.
	 */
	@Transactional
	public void ensureState(Long userId) {
		userCharacterMapper.insertStateIfAbsent(userId);
		userCharacterMapper.insertWalletIfAbsent(userId);
		userCharacterMapper.insertProgressIfAbsent(userId);
		userCharacterMapper.grantDefaultItemGroups(userId);
	}

	/**
	 * GET /characters — 선택 가능한 캐릭터 목록(온보딩 좌우 비교 + 교체 화면).
	 * MVP 에서 캐릭터는 전원 무료 개방이라 owned 는 항상 true 다(유료화 시 이 판정만 교체).
	 */
	@Transactional
	public CharacterListResponse getCharacters(Long userId) {
		ensureState(userId);
		String selected = selectedCharacterOf(userId);

		List<CharacterResponse> items = catalog.characters().stream()
				.map(c -> new CharacterResponse(
						c.code(), c.nameKo(), c.tagline(), c.thumbnailUrl(),
						true, Objects.equals(c.code(), selected)))
				.toList();
		return new CharacterListResponse(selected, items);
	}

	/**
	 * GET /characters/me — 캐릭터 홈이 한 번에 그리는 데 필요한 전부.
	 * ★ 캐릭터 미선택(온보딩 미완료)이어도 404 가 아니라 200 + {@code character: null} 이다(앱의 온보딩 분기 신호).
	 */
	@Transactional
	public MyCharacterResponse getMyCharacter(Long userId) {
		ensureState(userId);
		return buildMyCharacter(userId);
	}

	/**
	 * PUT /characters/me/selection — 캐릭터 선택/교체.
	 * 착용은 <b>그대로 유지</b>되고 variant 만 새 캐릭터 기준으로 재해석된다(user_equipment 미수정).
	 *
	 * <p>없는/비활성 코드 → 409 CHARACTER_NOT_OWNED(캐릭터는 전원 개방이라 '없는 코드'도 '보유 불가'로 수렴).
	 * 이미 착용 중인 group 의 새 캐릭터용 variant 가 미제작이면 → 409 ITEM_VARIANT_MISSING 으로 교체를 거부한다
	 * (교체를 허용하면 홈이 그 아이템을 못 그린 채 조용히 사라지므로, 원인을 명시적으로 알린다).
	 */
	@Transactional
	public MyCharacterResponse selectCharacter(Long userId, SelectCharacterRequest request) {
		ensureState(userId);

		CharacterRow target = catalog.character(request.characterCode());
		if (target == null) {
			throw new BusinessException(ErrorCode.CHARACTER_NOT_OWNED);
		}

		// 착용 중인 group 전부가 새 캐릭터로 해석되는지 선검증(하나라도 미제작이면 교체 거부 → 전체 롤백).
		for (String groupCode : userCharacterMapper.findEquippedGroupCodes(userId)) {
			if (catalog.resolveVariant(groupCode, target.code()) == null) {
				throw new BusinessException(ErrorCode.ITEM_VARIANT_MISSING,
						"착용 중인 아이템(" + groupCode + ")의 " + target.nameKo() + "용 이미지가 아직 없어요.");
			}
		}

		userCharacterMapper.updateSelectedCharacter(userId, target.code());
		return buildMyCharacter(userId);
	}

	/** 선택 캐릭터 코드(미선택이면 null). JIT 이후 호출이라 상태 행은 반드시 존재한다. */
	@Transactional(readOnly = true)
	public String selectedCharacterOf(Long userId) {
		UserCharacterStateRow state = userCharacterMapper.findState(userId);
		return state == null ? null : state.selectedCharacter();
	}

	/**
	 * 캐릭터 상태 조립(선택/착용 변경 API 의 공통 응답). 착용 목록의 variant 해석은 매퍼의 조인이 수행한다
	 * (WardrobeService 도 착용 변경 후 이 메서드로 응답을 만든다 — 응답 형태 단일화).
	 *
	 * <p>⚠️ 이 메서드는 {@link #ensureState(Long)} 를 호출하지 않는 <b>순수 조회</b>다(SELECT 4건).
	 * 따라서 <b>타인의 userId 로 호출해도 상태 행을 만들지 않아 안전</b>하며, 친구 둘러보기
	 * (FriendBrowseService) 가 이 성질에 의존한다. 상태 행이 없으면 {@code character = null} 로 폴백한다.
	 * <b>단 열람 권한 판정은 호출자 책임</b>이다(이 메서드는 권한을 보지 않는다).
	 */
	public MyCharacterResponse buildMyCharacter(Long userId) {
		UserCharacterStateRow state = userCharacterMapper.findState(userId);
		String selected = state == null ? null : state.selectedCharacter();

		CharacterRow row = catalog.character(selected);
		SelectedCharacterResponse character = row == null ? null
				: new SelectedCharacterResponse(row.code(), row.nameKo(), row.riveArtboard(), row.thumbnailUrl());

		Integer balance = userCharacterMapper.findWalletBalance(userId);
		int unacked = userCharacterMapper.countUnackedRewards(userId);

		List<EquippedItemResponse> equipment = userCharacterMapper.findEquippedItems(userId, selected).stream()
				.map(this::toEquippedResponse)
				.toList();

		return new MyCharacterResponse(character, balance == null ? 0 : balance, unacked, equipment);
	}

	private EquippedItemResponse toEquippedResponse(EquippedItemRow row) {
		return new EquippedItemResponse(row.slot(), row.slotIndex(), row.groupCode(), row.nameKo(),
				row.imageUrl(), row.riveSlot(), catalog.toJson(row.renderMeta()));
	}
}
