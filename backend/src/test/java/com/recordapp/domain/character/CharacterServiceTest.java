package com.recordapp.domain.character;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.character.dto.CharacterListResponse;
import com.recordapp.domain.character.dto.CharacterResponse;
import com.recordapp.domain.character.dto.EquipmentItemRequest;
import com.recordapp.domain.character.dto.EquippedItemResponse;
import com.recordapp.domain.character.dto.ItemGroupResponse;
import com.recordapp.domain.character.dto.MissionResponse;
import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.dto.SelectCharacterRequest;
import com.recordapp.domain.character.dto.UpdateEquipmentRequest;
import com.recordapp.domain.character.service.CatalogCache;
import com.recordapp.domain.character.service.CharacterService;
import com.recordapp.domain.character.service.MissionService;
import com.recordapp.domain.character.service.WardrobeService;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 캐릭터 도메인 통합 테스트(Testcontainers PostgreSQL 18) — Task 027 전 항목.
 *
 * <p>서비스 계층을 직접 호출해 HTTP·인증을 우회하고, <b>group↔variant 해석</b>·JIT 멱등·소유/슬롯 검증·
 * 배치 착용 원자성·IDOR 이 <b>실제 DB</b>에서 성립하는지 검증한다. 사용자 식별은 기존 통합테스트 관례대로
 * JIT 프로비저닝으로 users 행을 만들어 내부 userId 를 확보한다.
 *
 * <p>⚠️ 클래스/메서드에 {@code @Transactional} 을 두지 않는다(DiaryServiceTest·ResolutionIntegrationTest 동일).
 * 각 서비스 호출이 실제로 커밋돼야 "배치 교체 실패 시 이전 착용이 그대로 남아 있는가" 같은 검증이 의미를 갖는다.
 *
 * <p>테스트 전용 아이템 그룹은 시드를 오염시키지 않도록 고유 code 로 심고, {@link CatalogCache#reload()} 로
 * 카탈로그를 갱신한다(캐시가 마스터 변경을 반영하는지도 함께 검증된다). 이 때문에 목록 검증은
 * 정확한 개수가 아니라 <b>포함 관계</b>로 단언한다(다른 테스트가 심은 그룹과 무관하게 성립).
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class CharacterServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	// 시드(V15) 아이템 — 기본 지급 2종 + 미션 해금 2종 + 구매 1종.
	private static final String OUTFIT = "OUTFIT_BASIC_TEE";  // OUTFIT / DEFAULT (가입 시 소유)
	private static final String PLANT = "ROOM_PROP_PLANT";    // ROOM_PROP / DEFAULT (공용 variant)
	private static final String HAT_PARTY = "HAT_PARTY";      // HAT / MISSION (미소유)
	private static final String HAT_STRAW = "HAT_STRAW";      // HAT / COIN (미소유)
	private static final String BG = "BG_COZY_ROOM";          // BACKGROUND / MISSION (공용 variant)

	@Autowired
	CharacterService characterService;

	@Autowired
	WardrobeService wardrobeService;

	@Autowired
	MissionService missionService;

	@Autowired
	CatalogCache catalogCache;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	@BeforeEach
	void resetCache() {
		// 이전 테스트가 심은 테스트 그룹까지 반영된 최신 카탈로그로 시작한다.
		catalogCache.reload();
	}

	// ===== 헬퍼 =====

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	/** JIT 프로비저닝으로 회원 1명 생성 후 내부 PK 반환(테스트별 고유 uid → userId 격리). */
	private long newUser() {
		String sub = UUID.randomUUID().toString();
		return provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", "tester"), Map.of("sub", sub)))
				.userId();
	}

	/** 소유 부여(미션 해금·구매는 Task 028 소관이므로 테스트에서는 직접 심는다). */
	private void own(long userId, String groupCode) {
		jdbc().update("INSERT INTO user_item_groups (user_id, group_code) VALUES (?, ?) "
				+ "ON CONFLICT DO NOTHING", userId, groupCode);
	}

	private int rowCount(String table, long userId) {
		Integer n = jdbc().queryForObject(
				"SELECT count(*) FROM " + table + " WHERE user_id = ?", Integer.class, userId);
		return n == null ? 0 : n;
	}

	private EquipmentItemRequest item(String slot, int index, String groupCode) {
		return new EquipmentItemRequest(slot, (short) index, groupCode);
	}

	private MyCharacterResponse equip(long userId, EquipmentItemRequest... items) {
		return wardrobeService.replaceEquipment(userId, new UpdateEquipmentRequest(List.of(items)));
	}

	private MyCharacterResponse select(long userId, String code) {
		return characterService.selectCharacter(userId, new SelectCharacterRequest(code));
	}

	private EquippedItemResponse findEquipped(MyCharacterResponse me, String groupCode) {
		return me.equipment().stream()
				.filter(e -> e.groupCode().equals(groupCode))
				.findFirst()
				.orElseThrow(() -> new AssertionError("착용 목록에 없음: " + groupCode));
	}

	private ItemGroupResponse findItem(List<ItemGroupResponse> items, String groupCode) {
		return items.stream()
				.filter(i -> i.groupCode().equals(groupCode))
				.findFirst()
				.orElseThrow(() -> new AssertionError("아이템 목록에 없음: " + groupCode));
	}

	private MissionResponse findMission(List<MissionResponse> items, String code) {
		return items.stream()
				.filter(m -> m.code().equals(code))
				.findFirst()
				.orElseThrow(() -> new AssertionError("미션 목록에 없음: " + code));
	}

	/**
	 * 테스트 전용 아이템 그룹 + variant 를 심고 캐시를 갱신한다.
	 * acquireType 은 DEFAULT 를 쓰지 않는다(모든 사용자에게 자동 지급되어 다른 테스트를 오염시킨다).
	 *
	 * @param characterCode variant 의 캐릭터(null 이면 공용). 미제작 상황을 만들려면 한쪽만 심는다.
	 */
	private String newTestGroup(String slot, String characterCode) {
		String code = "T_" + slot + "_" + UUID.randomUUID().toString().substring(0, 8);
		jdbc().update("INSERT INTO item_groups (code, slot, name_ko, thumbnail_url, acquire_type) "
				+ "VALUES (?, ?, '테스트 아이템', 'assets/items/t.png', 'MISSION')", code, slot);
		jdbc().update("INSERT INTO character_items (group_code, character_code, image_url, rive_slot, render_meta) "
						+ "VALUES (?, ?, ?, 'test', '{\"scale\":1.0}'::jsonb)",
				code, characterCode, "assets/items/" + code.toLowerCase() + ".png");
		catalogCache.reload();
		return code;
	}

	// ===== 1) JIT 기본 상태: 멱등(동시 호출에도 각 1행) =====

	@Test
	void ensureState_isIdempotent_underConcurrency() throws Exception {
		long userId = newUser();

		// 동시 2회 호출 — ON CONFLICT DO NOTHING 이 각 1행을 보장해야 한다.
		ExecutorService pool = Executors.newFixedThreadPool(2);
		CountDownLatch start = new CountDownLatch(1);
		for (int i = 0; i < 2; i++) {
			pool.submit(() -> {
				start.await();
				characterService.ensureState(userId);
				return null;
			});
		}
		start.countDown();
		pool.shutdown();
		assertThat(pool.awaitTermination(20, TimeUnit.SECONDS)).isTrue();

		assertThat(rowCount("user_character_state", userId)).as("상태 1행").isEqualTo(1);
		assertThat(rowCount("user_wallets", userId)).as("지갑 1행").isEqualTo(1);
		assertThat(rowCount("user_progress", userId)).as("진척도 1행").isEqualTo(1);

		// 재호출해도 여전히 1행(멱등).
		characterService.ensureState(userId);
		assertThat(rowCount("user_character_state", userId)).isEqualTo(1);
		assertThat(rowCount("user_wallets", userId)).isEqualTo(1);
		assertThat(rowCount("user_progress", userId)).isEqualTo(1);

		// 기본 지급(DEFAULT) 아이템 소유도 중복되지 않는다.
		Integer owned = jdbc().queryForObject(
				"SELECT count(*) FROM user_item_groups WHERE user_id = ? AND group_code = ?",
				Integer.class, userId, OUTFIT);
		assertThat(owned).as("기본 지급 아이템 소유 1행").isEqualTo(1);
	}

	// ===== 2) GET /characters: 2종 + 선택 전 selected=false =====

	@Test
	void getCharacters_returnsTwoCharacters_unselectedByDefault() {
		long userId = newUser();

		CharacterListResponse res = characterService.getCharacters(userId);

		assertThat(res.selectedCharacter()).as("온보딩 미완료 → null").isNull();
		assertThat(res.items()).extracting(CharacterResponse::code)
				.containsExactly("MONKEY", "RED_PANDA"); // sort_order 순
		assertThat(res.items()).allSatisfy(c -> {
			assertThat(c.owned()).as("캐릭터는 전원 무료 개방").isTrue();
			assertThat(c.selected()).isFalse();
			// 온보딩 캐러셀이 쓰는 필드가 모두 채워져 있어야 한다.
			assertThat(c.nameKo()).isNotBlank();
			assertThat(c.tagline()).isNotBlank();
			assertThat(c.thumbnailUrl()).isNotBlank();
		});
	}

	// ===== 3) GET /characters/me: 미선택 사용자도 정상 응답(404 아님) =====

	@Test
	void getMyCharacter_unselectedUser_returnsNullCharacterWithDefaults() {
		long userId = newUser();

		MyCharacterResponse me = characterService.getMyCharacter(userId);

		assertThat(me.character()).as("앱은 이 null 로 온보딩을 띄운다").isNull();
		assertThat(me.level()).isEqualTo(1);
		assertThat(me.exp()).isZero();
		assertThat(me.expToNext()).isEqualTo(CharacterConstants.EXP_PER_LEVEL);
		assertThat(me.coinBalance()).isZero();
		assertThat(me.unackedRewardCount()).isZero();
		assertThat(me.equipment()).isEmpty();
	}

	// ===== 4) 선택 저장 → /characters/me·/characters 에 반영 =====

	@Test
	void selectCharacter_isReflectedInMyCharacterAndList() {
		long userId = newUser();

		MyCharacterResponse me = select(userId, "MONKEY");
		assertThat(me.character()).isNotNull();
		assertThat(me.character().code()).isEqualTo("MONKEY");
		assertThat(me.character().nameKo()).isEqualTo("원숭이");
		assertThat(me.character().riveArtboard()).isEqualTo("monkey");

		assertThat(characterService.getMyCharacter(userId).character().code()).isEqualTo("MONKEY");

		CharacterListResponse list = characterService.getCharacters(userId);
		assertThat(list.selectedCharacter()).isEqualTo("MONKEY");
		assertThat(list.items()).filteredOn(c -> c.code().equals("MONKEY"))
				.allSatisfy(c -> assertThat(c.selected()).isTrue());
		assertThat(list.items()).filteredOn(c -> c.code().equals("RED_PANDA"))
				.allSatisfy(c -> assertThat(c.selected()).isFalse());
	}

	@Test
	void selectCharacter_unknownCode_throwsCharacterNotOwned() {
		long userId = newUser();

		assertThatThrownBy(() -> select(userId, "CAT"))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.CHARACTER_NOT_OWNED));
	}

	// ===== 5) ★★ 핵심: 캐릭터 교체 시 착용 유지 + variant 재해석 ★★ =====

	@Test
	void swapCharacter_keepsEquipment_andReresolvesVariantOnly() {
		long userId = newUser();
		own(userId, HAT_PARTY); // 미션 보상 아이템을 직접 소유시킨다(지급은 Task 028 소관).

		// MONKEY 로 후드티(OUTFIT) + 파티모자(HAT) + 화분(ROOM_PROP, 공용) 착용.
		select(userId, "MONKEY");
		MyCharacterResponse monkey = equip(userId,
				item("OUTFIT", 0, OUTFIT),
				item("HAT", 0, HAT_PARTY),
				item("ROOM_PROP", 0, PLANT));

		assertThat(findEquipped(monkey, OUTFIT).imageUrl())
				.isEqualTo("assets/items/outfit_basic_tee_monkey.png");
		assertThat(findEquipped(monkey, HAT_PARTY).imageUrl())
				.isEqualTo("assets/items/hat_party_monkey.png");
		// 공용 variant(character_code IS NULL) — 캐릭터와 무관하게 해석된다.
		assertThat(findEquipped(monkey, PLANT).imageUrl())
				.isEqualTo("assets/items/room_prop_plant.png");
		// render_meta(JSONB) 왕복 — 플레이스홀더 렌더러(Task 029)가 쓰는 좌표.
		assertThat(findEquipped(monkey, OUTFIT).renderMeta().get("anchorY").asDouble()).isEqualTo(0.55);
		assertThat(findEquipped(monkey, OUTFIT).riveSlot()).isEqualTo("outfit");

		// ★ RED_PANDA 로 교체 — user_equipment 는 건드리지 않는다.
		MyCharacterResponse panda = select(userId, "RED_PANDA");

		assertThat(panda.character().code()).isEqualTo("RED_PANDA");
		// 착용 group_code 는 그대로(옷장이 캐릭터를 따라온다).
		assertThat(panda.equipment()).extracting(EquippedItemResponse::groupCode)
				.containsExactlyInAnyOrder(OUTFIT, HAT_PARTY, PLANT);
		assertThat(panda.equipment()).hasSize(3);
		// image_url 만 RED_PANDA variant 로 재해석된다.
		assertThat(findEquipped(panda, OUTFIT).imageUrl())
				.isEqualTo("assets/items/outfit_basic_tee_red_panda.png");
		assertThat(findEquipped(panda, HAT_PARTY).imageUrl())
				.isEqualTo("assets/items/hat_party_red_panda.png");
		// 체형 보정된 render_meta 도 함께 바뀐다(원숭이 0.55 → 레서판다 0.58).
		assertThat(findEquipped(panda, OUTFIT).renderMeta().get("anchorY").asDouble()).isEqualTo(0.58);
		// 공용 variant 는 캐릭터가 바뀌어도 동일.
		assertThat(findEquipped(panda, PLANT).imageUrl())
				.isEqualTo("assets/items/room_prop_plant.png");

		// DB 상으로도 착용 행은 3행 그대로(교체는 selected_character 만 갱신).
		assertThat(rowCount("user_equipment", userId)).isEqualTo(3);
	}

	// ===== 6) 착용 검증: 미보유(409) / 슬롯 불일치(400) / variant 미제작(409) =====

	@Test
	void equip_notOwnedGroup_throwsItemNotOwned() {
		long userId = newUser();
		select(userId, "MONKEY");

		// HAT_STRAW 는 COIN 아이템 → 기본 지급 대상이 아니다.
		assertThatThrownBy(() -> equip(userId, item("HAT", 0, HAT_STRAW)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_NOT_OWNED));
		assertThat(rowCount("user_equipment", userId)).isZero();

		// 존재하지 않는 그룹도 같은 코드로 수렴(정보 노출 최소화).
		assertThatThrownBy(() -> equip(userId, item("HAT", 0, "NO_SUCH_GROUP")))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_NOT_OWNED));
	}

	@Test
	void equip_slotMismatch_throwsItemSlotMismatch() {
		long userId = newUser();
		select(userId, "MONKEY");

		// OUTFIT 그룹(소유 중)을 HAT 슬롯에 착용 시도 → DB 는 못 막는 규칙이라 서비스가 400 으로 막는다.
		assertThatThrownBy(() -> equip(userId, item("HAT", 0, OUTFIT)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_SLOT_MISMATCH));
		assertThat(rowCount("user_equipment", userId)).isZero();
	}

	@Test
	void equip_variantMissingForSelectedCharacter_throwsItemVariantMissing() {
		long userId = newUser();
		select(userId, "MONKEY");

		// RED_PANDA 용 variant 만 제작된 그룹 → MONKEY 로는 그릴 수 없다.
		String pandaOnly = newTestGroup("HAT", "RED_PANDA");
		own(userId, pandaOnly);

		assertThatThrownBy(() -> equip(userId, item("HAT", 0, pandaOnly)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_VARIANT_MISSING));

		// RED_PANDA 로 바꾸면 정상 착용된다(같은 group, 다른 캐릭터).
		select(userId, "RED_PANDA");
		assertThatCode(() -> equip(userId, item("HAT", 0, pandaOnly))).doesNotThrowAnyException();
		assertThat(characterService.getMyCharacter(userId).equipment())
				.extracting(EquippedItemResponse::groupCode).contains(pandaOnly);
	}

	@Test
	void selectCharacter_whenEquippedVariantMissingForTarget_isRejectedAndRollsBack() {
		long userId = newUser();
		select(userId, "RED_PANDA");

		// RED_PANDA 전용 variant 만 있는 그룹을 착용한 상태에서 MONKEY 로 교체 시도.
		String pandaOnly = newTestGroup("HAT", "RED_PANDA");
		own(userId, pandaOnly);
		equip(userId, item("HAT", 0, pandaOnly));

		assertThatThrownBy(() -> select(userId, "MONKEY"))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_VARIANT_MISSING));

		// 교체가 거부됐으므로 선택 캐릭터·착용은 그대로다(전체 롤백).
		MyCharacterResponse me = characterService.getMyCharacter(userId);
		assertThat(me.character().code()).isEqualTo("RED_PANDA");
		assertThat(me.equipment()).extracting(EquippedItemResponse::groupCode).contains(pandaOnly);
	}

	// ===== 7) 배치 교체: 원자성(5개 중 3번째 미보유 → 전체 롤백) =====

	@Test
	void replaceEquipment_isAtomic_whenOneItemFails() {
		long userId = newUser();
		own(userId, HAT_PARTY);
		own(userId, BG);
		select(userId, "MONKEY");

		// 사전 상태: 후드티만 착용.
		equip(userId, item("OUTFIT", 0, OUTFIT));
		assertThat(rowCount("user_equipment", userId)).isEqualTo(1);

		// 5개 배치 중 3번째(HAT_STRAW)가 미보유 → 전체 실패해야 한다(1·2번도 반영 안 됨).
		List<EquipmentItemRequest> batch = List.of(
				item("OUTFIT", 0, OUTFIT),
				item("ROOM_PROP", 0, PLANT),
				item("HAT", 0, HAT_STRAW),   // ★ 미보유
				item("BACKGROUND", 0, BG),
				item("ROOM_PROP", 1, HAT_PARTY));

		assertThatThrownBy(() -> wardrobeService.replaceEquipment(userId, new UpdateEquipmentRequest(batch)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_NOT_OWNED));

		// 이전 착용(후드티 1행)이 그대로 남아 있어야 한다 — DELETE 도 INSERT 도 일어나지 않았다.
		assertThat(rowCount("user_equipment", userId)).as("전체 롤백").isEqualTo(1);
		assertThat(characterService.getMyCharacter(userId).equipment())
				.extracting(EquippedItemResponse::groupCode).containsExactly(OUTFIT);
	}

	// ===== 8) ROOM_PROP 0~5 다중 진열 / 단일 슬롯 중복 거부 / 빈 배치 해제 =====

	@Test
	void replaceEquipment_roomPropMulti_singleSlotDuplicateRejected_emptyBatchClears() {
		long userId = newUser();
		select(userId, "MONKEY");

		// ROOM_PROP 6칸(0~5)을 채우려면 공용 variant 그룹 6개가 필요하다(같은 group 중복 진열은 금지).
		List<EquipmentItemRequest> props = new ArrayList<>();
		props.add(item("ROOM_PROP", 0, PLANT)); // 시드(공용 variant)
		for (int i = 1; i <= 5; i++) {
			String prop = newTestGroup("ROOM_PROP", null); // 공용 variant
			own(userId, prop);
			props.add(item("ROOM_PROP", i, prop));
		}

		MyCharacterResponse me = wardrobeService.replaceEquipment(userId, new UpdateEquipmentRequest(props));
		assertThat(me.equipment()).as("ROOM_PROP 0~5 다중 진열").hasSize(6);
		assertThat(me.equipment()).extracting(EquippedItemResponse::slotIndex)
				.containsExactly((short) 0, (short) 1, (short) 2, (short) 3, (short) 4, (short) 5);
		// 공용 variant 는 캐릭터 미지정이므로 캐릭터가 무엇이든 해석된다.
		assertThat(me.equipment()).allSatisfy(e -> assertThat(e.imageUrl()).isNotBlank());

		// 단일 슬롯(HAT)에 2개 착용 시도 → 같은 칸 중복이라 400.
		own(userId, HAT_PARTY);
		assertThatThrownBy(() -> equip(userId,
				item("HAT", 0, HAT_PARTY),
				item("HAT", 0, OUTFIT)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.VALIDATION_ERROR));

		// 단일 슬롯에 slot_index > 0 → 400(DB CHECK 이전에 서비스가 막는다).
		assertThatThrownBy(() -> equip(userId, item("HAT", 1, HAT_PARTY)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.VALIDATION_ERROR));

		// 실패한 요청들이 기존 착용(6행)을 건드리지 않았다.
		assertThat(rowCount("user_equipment", userId)).isEqualTo(6);

		// 빈 배치 → 전 슬롯 해제.
		MyCharacterResponse cleared = wardrobeService.replaceEquipment(userId, new UpdateEquipmentRequest(List.of()));
		assertThat(cleared.equipment()).isEmpty();
		assertThat(rowCount("user_equipment", userId)).isZero();
	}

	// ===== 9) GET /characters/items: 소유 여부 + 내 캐릭터 기준 variant + lockedBy =====

	@Test
	void getItems_returnsOwnershipAndCharacterVariant() {
		long userId = newUser();
		select(userId, "MONKEY");
		equip(userId, item("OUTFIT", 0, OUTFIT));

		List<ItemGroupResponse> hats = wardrobeService.getItems(userId, "HAT").items();
		assertThat(hats).allSatisfy(i -> assertThat(i.slot().name()).isEqualTo("HAT")); // slot 필터

		ItemGroupResponse party = findItem(hats, HAT_PARTY);
		assertThat(party.owned()).isFalse();
		assertThat(party.equipped()).isFalse();
		assertThat(party.acquireType().name()).isEqualTo("MISSION");
		assertThat(party.imageUrl()).as("내 캐릭터(MONKEY) 기준 variant")
				.isEqualTo("assets/items/hat_party_monkey.png");
		assertThat(party.renderMeta().get("z").asInt()).isEqualTo(40);
		// MISSION 해금 아이템 + 미보유 → 해금 진행률(lockedBy) 노출.
		assertThat(party.lockedBy()).isNotNull();
		assertThat(party.lockedBy().missionCode()).isEqualTo("DIARY_10");
		assertThat(party.lockedBy().threshold()).isEqualTo(10);
		assertThat(party.lockedBy().progress()).isZero();

		ItemGroupResponse straw = findItem(hats, HAT_STRAW);
		assertThat(straw.acquireType().name()).isEqualTo("COIN");
		assertThat(straw.coinPrice()).isEqualTo(120);
		assertThat(straw.lockedBy()).as("구매 아이템은 미션 잠금이 아니다").isNull();

		// 소유·착용 플래그(OUTFIT 탭).
		ItemGroupResponse outfit = findItem(wardrobeService.getItems(userId, "OUTFIT").items(), OUTFIT);
		assertThat(outfit.owned()).as("기본 지급 → 소유").isTrue();
		assertThat(outfit.equipped()).isTrue();
		assertThat(outfit.lockedBy()).as("보유 중이면 잠금 없음").isNull();

		// RED_PANDA 로 바꾸면 같은 목록의 imageUrl 만 바뀐다.
		select(userId, "RED_PANDA");
		assertThat(findItem(wardrobeService.getItems(userId, "HAT").items(), HAT_PARTY).imageUrl())
				.isEqualTo("assets/items/hat_party_red_panda.png");

		// slot 생략 → 전체 슬롯(HAT·OUTFIT·ROOM_PROP·BACKGROUND 가 모두 포함).
		List<ItemGroupResponse> all = wardrobeService.getItems(userId, null).items();
		assertThat(all).extracting(ItemGroupResponse::groupCode)
				.contains(OUTFIT, PLANT, HAT_PARTY, HAT_STRAW, BG);
	}

	@Test
	void getItems_excludesGroupsWithoutVariantForMyCharacter() {
		long userId = newUser();
		select(userId, "MONKEY");

		// RED_PANDA 전용 variant 만 있는 그룹 → MONKEY 목록에서는 제외(그릴 수 없는 항목을 노출하지 않는다).
		String pandaOnly = newTestGroup("HAT", "RED_PANDA");

		assertThat(wardrobeService.getItems(userId, "HAT").items())
				.extracting(ItemGroupResponse::groupCode).doesNotContain(pandaOnly);

		select(userId, "RED_PANDA");
		assertThat(wardrobeService.getItems(userId, "HAT").items())
				.extracting(ItemGroupResponse::groupCode).contains(pandaOnly);
	}

	// ===== 10) GET /missions: 달성 여부 + 진행률(user_progress O(1)) =====

	@Test
	void getMissions_computesProgressFromUserProgress() {
		long userId = newUser();
		characterService.ensureState(userId);

		// 초기: 전부 0 / 미달성.
		List<MissionResponse> initial = missionService.getMissions(userId).items();
		assertThat(initial).extracting(MissionResponse::code)
				.contains("DIARY_10", "STREAK_7", "RESOL_1", "RESOL_STREAK_3", "LEVEL_5");
		assertThat(findMission(initial, "DIARY_10").progress()).isZero();
		assertThat(findMission(initial, "DIARY_10").achieved()).isFalse();
		assertThat(findMission(initial, "DIARY_10").achievedAt()).isNull();
		// LEVEL 규칙은 user_character_state.level(기본 1)을 본다.
		assertThat(findMission(initial, "LEVEL_5").progress()).isEqualTo(1);
		assertThat(findMission(initial, "LEVEL_5").threshold()).isEqualTo(5);

		// 진척도 갱신(보상 엔진의 UPSERT 를 시뮬레이션).
		jdbc().update("UPDATE user_progress SET confirmed_diary_count = 7, consecutive_days = 7, "
				+ "resolution_success_count = 1, max_streak_seq = 2 WHERE user_id = ?", userId);
		jdbc().update("UPDATE user_character_state SET level = 3 WHERE user_id = ?", userId);

		List<MissionResponse> after = missionService.getMissions(userId).items();
		MissionResponse diary10 = findMission(after, "DIARY_10");
		assertThat(diary10.progress()).as("10개 중 7개 → 70%").isEqualTo(7);
		assertThat(diary10.threshold()).isEqualTo(10);
		assertThat(diary10.rule().type().name()).isEqualTo("DIARY_COUNT");
		assertThat(diary10.rule().threshold()).isEqualTo(10);
		assertThat(diary10.coinReward()).isEqualTo(50);
		assertThat(diary10.itemGroupReward()).isEqualTo(HAT_PARTY);
		// 규칙 타입별로 서로 다른 컬럼을 본다(임계값 키 정규화: count/days/seq/level → threshold).
		assertThat(findMission(after, "STREAK_7").progress()).isEqualTo(7);          // consecutive_days
		assertThat(findMission(after, "RESOL_1").progress()).isEqualTo(1);           // resolution_success_count
		assertThat(findMission(after, "RESOL_STREAK_3").progress()).isEqualTo(2);    // max_streak_seq
		assertThat(findMission(after, "LEVEL_5").progress()).isEqualTo(3);           // level

		// 임계값을 넘겨도 달성(achieved)은 이력(user_missions)이 있어야 true — 지급은 Task 028 소관.
		assertThat(findMission(after, "STREAK_7").achieved()).isFalse();
		jdbc().update("INSERT INTO user_missions (user_id, mission_code) VALUES (?, 'STREAK_7')", userId);

		MissionResponse streak = findMission(missionService.getMissions(userId).items(), "STREAK_7");
		assertThat(streak.achieved()).isTrue();
		assertThat(streak.achievedAt()).isNotNull();

		// 해금된 아이템(BG_COZY_ROOM)은 lockedBy 진행률에도 반영된다.
		ItemGroupResponse bg = findItem(wardrobeService.getItems(userId, "BACKGROUND").items(), BG);
		assertThat(bg.lockedBy()).isNotNull();  // 아직 소유는 아님(지급은 Task 028)
		assertThat(bg.lockedBy().progress()).isEqualTo(7);
		assertThat(bg.lockedBy().threshold()).isEqualTo(7);
	}

	// ===== 11) IDOR: 타인 상태를 조회·변경할 수 없다 =====

	@Test
	void authz_userStateIsIsolatedByUserId() {
		long owner = newUser();
		long other = newUser();

		own(owner, HAT_PARTY);
		select(owner, "MONKEY");
		equip(owner, item("OUTFIT", 0, OUTFIT), item("HAT", 0, HAT_PARTY));

		// 다른 사용자는 자기 상태만 본다(선택 없음·착용 없음).
		MyCharacterResponse otherMe = characterService.getMyCharacter(other);
		assertThat(otherMe.character()).isNull();
		assertThat(otherMe.equipment()).isEmpty();

		// 다른 사용자가 캐릭터를 바꾸고 착용을 비워도 owner 상태는 불변(userId 로만 대상을 좁히므로).
		select(other, "RED_PANDA");
		wardrobeService.replaceEquipment(other, new UpdateEquipmentRequest(List.of()));

		MyCharacterResponse ownerMe = characterService.getMyCharacter(owner);
		assertThat(ownerMe.character().code()).isEqualTo("MONKEY");
		assertThat(ownerMe.equipment()).extracting(EquippedItemResponse::groupCode)
				.containsExactlyInAnyOrder(OUTFIT, HAT_PARTY);
		assertThat(rowCount("user_equipment", owner)).isEqualTo(2);
		assertThat(rowCount("user_equipment", other)).isZero();

		// owner 의 소유 아이템을 other 가 착용할 수는 없다(소유는 사용자별).
		assertThatThrownBy(() -> equip(other, item("HAT", 0, HAT_PARTY)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_NOT_OWNED));
	}
}
