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
 * 캐릭터 도메인 통합 테스트(Testcontainers PostgreSQL 18) — Task 027 + V21 카탈로그.
 *
 * <p>서비스 계층을 직접 호출해 HTTP·인증을 우회하고, <b>group↔variant 해석</b>·JIT 멱등·소유/슬롯 검증·
 * 배치 착용 원자성·IDOR 이 <b>실제 DB</b>에서 성립하는지 검증한다. 사용자 식별은 기존 통합테스트 관례대로
 * JIT 프로비저닝으로 users 행을 만들어 내부 userId 를 확보한다.
 *
 * <p>⚠️ 클래스/메서드에 {@code @Transactional} 을 두지 않는다(DiaryServiceTest·ResolutionIntegrationTest 동일).
 * 각 서비스 호출이 실제로 커밋돼야 "배치 교체 실패 시 이전 착용이 그대로 남아 있는가" 같은 검증이 의미를 갖는다.
 *
 * <p>V21 카탈로그는 <b>부위별 착용 5종(HAT/GLASSES/OUTFIT/BOTTOM/SHOES) 전부 COIN·미보유(잠금)</b>이다.
 * DEFAULT 아이템이 없어 신규 유저는 아무것도 소유하지 않으므로, 착용 흐름 검증은 {@link #own} 헬퍼로
 * 소유를 직접 부여한다(구매는 Task 028 잔여). 테스트 전용 그룹은 시드를 오염시키지 않게 고유 code 로 심고
 * {@link CatalogCache#reload()} 로 갱신한다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class CharacterServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	// V21 카탈로그 5종(전부 COIN·미보유). 슬롯당 1종.
	private static final String HAT = "HAT_CAP_BLACK";        // HAT / COIN 15
	private static final String GLASSES = "GLASSES_ROUND";    // GLASSES / COIN 15
	private static final String OUTFIT = "OUTFIT_LOVE_HOOD";  // OUTFIT / COIN 50
	private static final String BOTTOM = "BOTTOM_CARGO_SAND"; // BOTTOM / COIN 50
	private static final String SHOES = "SHOES_MAX95";        // SHOES / COIN 20

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

	/** 소유 부여(5종 전부 COIN·미보유이고 구매는 Task 028 잔여이므로 테스트에서 직접 심는다). */
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
	 * 테스트 전용 아이템 그룹 + variant 를 심고 캐시를 갱신한다. acquireType 은 MISSION 을 써 시드를 오염시키지 않는다.
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

		// V21: DEFAULT 아이템이 없어 기본 지급이 없다 → 신규 유저는 아무것도 소유하지 않는다.
		assertThat(rowCount("user_item_groups", userId)).as("기본 지급 없음(전부 COIN·잠금)").isZero();
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
		own(userId, HAT);
		own(userId, OUTFIT);

		// MONKEY 로 모자(HAT) + 후드(OUTFIT) 착용.
		select(userId, "MONKEY");
		MyCharacterResponse monkey = equip(userId,
				item("HAT", 0, HAT),
				item("OUTFIT", 0, OUTFIT));

		assertThat(findEquipped(monkey, HAT).imageUrl())
				.isEqualTo("assets/items/hat_cap_black_monkey.png");
		assertThat(findEquipped(monkey, OUTFIT).imageUrl())
				.isEqualTo("assets/items/outfit_love_hood_monkey.png");
		// render_meta(JSONB) 왕복 — 렌더러가 쓰는 좌표.
		assertThat(findEquipped(monkey, HAT).renderMeta().get("anchorY").asDouble()).isEqualTo(0.18);
		assertThat(findEquipped(monkey, HAT).riveSlot()).isEqualTo("hat");

		// ★ RED_PANDA 로 교체 — user_equipment 는 건드리지 않는다.
		MyCharacterResponse panda = select(userId, "RED_PANDA");

		assertThat(panda.character().code()).isEqualTo("RED_PANDA");
		// 착용 group_code 는 그대로(옷장이 캐릭터를 따라온다).
		assertThat(panda.equipment()).extracting(EquippedItemResponse::groupCode)
				.containsExactlyInAnyOrder(HAT, OUTFIT);
		assertThat(panda.equipment()).hasSize(2);
		// image_url 만 RED_PANDA variant 로 재해석된다.
		assertThat(findEquipped(panda, HAT).imageUrl())
				.isEqualTo("assets/items/hat_cap_black_red_panda.png");
		assertThat(findEquipped(panda, OUTFIT).imageUrl())
				.isEqualTo("assets/items/outfit_love_hood_red_panda.png");
		// 체형 보정된 render_meta 도 함께 바뀐다(원숭이 0.18 → 레서판다 0.16).
		assertThat(findEquipped(panda, HAT).renderMeta().get("anchorY").asDouble()).isEqualTo(0.16);

		// DB 상으로도 착용 행은 2행 그대로(교체는 selected_character 만 갱신).
		assertThat(rowCount("user_equipment", userId)).isEqualTo(2);
	}

	// ===== 6) 착용 검증: 미보유(409) / 슬롯 불일치(400) / variant 미제작(409) =====

	@Test
	void equip_notOwnedGroup_throwsItemNotOwned() {
		long userId = newUser();
		select(userId, "MONKEY");

		// SHOES 는 COIN 아이템 → 미보유.
		assertThatThrownBy(() -> equip(userId, item("SHOES", 0, SHOES)))
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
		own(userId, OUTFIT);
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
		own(userId, HAT);
		own(userId, GLASSES);
		own(userId, BOTTOM);
		select(userId, "MONKEY");

		// 사전 상태: 후드만 착용(OUTFIT 은 소유시켜 둔다).
		own(userId, OUTFIT);
		equip(userId, item("OUTFIT", 0, OUTFIT));
		assertThat(rowCount("user_equipment", userId)).isEqualTo(1);

		// 5개 배치 중 3번째(SHOES)가 미보유 → 전체 실패해야 한다(1·2번도 반영 안 됨).
		List<EquipmentItemRequest> batch = List.of(
				item("OUTFIT", 0, OUTFIT),
				item("GLASSES", 0, GLASSES),
				item("SHOES", 0, SHOES),   // ★ 미보유
				item("HAT", 0, HAT),
				item("BOTTOM", 0, BOTTOM));

		assertThatThrownBy(() -> wardrobeService.replaceEquipment(userId, new UpdateEquipmentRequest(batch)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_NOT_OWNED));

		// 이전 착용(후드 1행)이 그대로 남아 있어야 한다 — DELETE 도 INSERT 도 일어나지 않았다.
		assertThat(rowCount("user_equipment", userId)).as("전체 롤백").isEqualTo(1);
		assertThat(characterService.getMyCharacter(userId).equipment())
				.extracting(EquippedItemResponse::groupCode).containsExactly(OUTFIT);
	}

	// ===== 8) ROOM_PROP 0~5 다중 진열 / 단일 슬롯 중복 거부 / 빈 배치 해제 =====

	@Test
	void replaceEquipment_roomPropMulti_singleSlotDuplicateRejected_emptyBatchClears() {
		long userId = newUser();
		select(userId, "MONKEY");

		// ROOM_PROP 6칸(0~5)을 채우려면 공용 variant 그룹 6개가 필요하다(V21 시드엔 ROOM_PROP 이 없어 테스트 그룹으로 심는다).
		List<EquipmentItemRequest> props = new ArrayList<>();
		for (int i = 0; i <= 5; i++) {
			String prop = newTestGroup("ROOM_PROP", null); // 공용 variant
			own(userId, prop);
			props.add(item("ROOM_PROP", i, prop));
		}

		MyCharacterResponse me = wardrobeService.replaceEquipment(userId, new UpdateEquipmentRequest(props));
		assertThat(me.equipment()).as("ROOM_PROP 0~5 다중 진열").hasSize(6);
		assertThat(me.equipment()).extracting(EquippedItemResponse::slotIndex)
				.containsExactly((short) 0, (short) 1, (short) 2, (short) 3, (short) 4, (short) 5);
		assertThat(me.equipment()).allSatisfy(e -> assertThat(e.imageUrl()).isNotBlank());

		// 단일 슬롯(HAT)에 2개 착용 시도 → 같은 칸 중복이라 400.
		own(userId, HAT);
		own(userId, OUTFIT);
		assertThatThrownBy(() -> equip(userId,
				item("HAT", 0, HAT),
				item("HAT", 0, OUTFIT)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.VALIDATION_ERROR));

		// 단일 슬롯에 slot_index > 0 → 400(DB CHECK 이전에 서비스가 막는다).
		assertThatThrownBy(() -> equip(userId, item("HAT", 1, HAT)))
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

	// ===== 9) GET /characters/items: 소유 여부 + 내 캐릭터 기준 variant + 가격 =====

	@Test
	void getItems_returnsOwnershipAndCharacterVariant() {
		long userId = newUser();
		select(userId, "MONKEY");
		own(userId, HAT);
		equip(userId, item("HAT", 0, HAT));

		List<ItemGroupResponse> hats = wardrobeService.getItems(userId, "HAT").items();
		assertThat(hats).allSatisfy(i -> assertThat(i.slot().name()).isEqualTo("HAT")); // slot 필터

		// 보유·착용 중인 모자.
		ItemGroupResponse hat = findItem(hats, HAT);
		assertThat(hat.owned()).isTrue();
		assertThat(hat.equipped()).isTrue();
		assertThat(hat.acquireType().name()).isEqualTo("COIN");
		assertThat(hat.coinPrice()).isEqualTo(15);
		assertThat(hat.imageUrl()).as("내 캐릭터(MONKEY) 기준 variant")
				.isEqualTo("assets/items/hat_cap_black_monkey.png");
		assertThat(hat.renderMeta().get("z").asInt()).isEqualTo(40);
		assertThat(hat.lockedBy()).as("COIN 아이템은 미션 잠금이 아니다").isNull();

		// 미보유 COIN 아이템(신발) — 가격 노출, 미션 잠금 아님.
		ItemGroupResponse shoes = findItem(
				wardrobeService.getItems(userId, "SHOES").items(), SHOES);
		assertThat(shoes.owned()).isFalse();
		assertThat(shoes.acquireType().name()).isEqualTo("COIN");
		assertThat(shoes.coinPrice()).isEqualTo(20);
		assertThat(shoes.lockedBy()).isNull();

		// RED_PANDA 로 바꾸면 같은 목록의 imageUrl 만 바뀐다.
		select(userId, "RED_PANDA");
		assertThat(findItem(wardrobeService.getItems(userId, "HAT").items(), HAT).imageUrl())
				.isEqualTo("assets/items/hat_cap_black_red_panda.png");

		// slot 생략 → 5종 전체가 포함된다.
		List<ItemGroupResponse> all = wardrobeService.getItems(userId, null).items();
		assertThat(all).extracting(ItemGroupResponse::groupCode)
				.contains(HAT, GLASSES, OUTFIT, BOTTOM, SHOES);
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
				.contains("DIARY_10", "STREAK_7", "RESOL_1", "RESOL_STREAK_3");
		assertThat(findMission(initial, "DIARY_10").progress()).isZero();
		assertThat(findMission(initial, "DIARY_10").achieved()).isFalse();
		assertThat(findMission(initial, "DIARY_10").achievedAt()).isNull();

		// 진척도 갱신(보상 엔진의 UPSERT 를 시뮬레이션).
		jdbc().update("UPDATE user_progress SET confirmed_diary_count = 7, consecutive_days = 7, "
				+ "resolution_success_count = 1, max_streak_seq = 2 WHERE user_id = ?", userId);

		List<MissionResponse> after = missionService.getMissions(userId).items();
		MissionResponse diary10 = findMission(after, "DIARY_10");
		assertThat(diary10.progress()).as("10개 중 7개").isEqualTo(7);
		assertThat(diary10.threshold()).isEqualTo(10);
		assertThat(diary10.rule().type().name()).isEqualTo("DIARY_COUNT");
		assertThat(diary10.rule().threshold()).isEqualTo(10);
		assertThat(diary10.coinReward()).isEqualTo(50);
		// V21: 미션 아이템 보상은 제거됐다(item_group_reward = NULL).
		assertThat(diary10.itemGroupReward()).isNull();
		// 규칙 타입별로 서로 다른 컬럼을 본다(임계값 키 정규화: count/days/seq → threshold).
		assertThat(findMission(after, "STREAK_7").progress()).isEqualTo(7);          // consecutive_days
		assertThat(findMission(after, "RESOL_1").progress()).isEqualTo(1);           // resolution_success_count
		assertThat(findMission(after, "RESOL_STREAK_3").progress()).isEqualTo(2);    // max_streak_seq
		assertThat(findMission(after, "STREAK_7").itemGroupReward()).isNull();

		// 임계값을 넘겨도 달성(achieved)은 이력(user_missions)이 있어야 true — 지급은 Task 028 소관.
		assertThat(findMission(after, "STREAK_7").achieved()).isFalse();
		jdbc().update("INSERT INTO user_missions (user_id, mission_code) VALUES (?, 'STREAK_7')", userId);

		MissionResponse streak = findMission(missionService.getMissions(userId).items(), "STREAK_7");
		assertThat(streak.achieved()).isTrue();
		assertThat(streak.achievedAt()).isNotNull();
	}

	// ===== 11) IDOR: 타인 상태를 조회·변경할 수 없다 =====

	@Test
	void authz_userStateIsIsolatedByUserId() {
		long owner = newUser();
		long other = newUser();

		own(owner, HAT);
		own(owner, OUTFIT);
		select(owner, "MONKEY");
		equip(owner, item("HAT", 0, HAT), item("OUTFIT", 0, OUTFIT));

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
				.containsExactlyInAnyOrder(HAT, OUTFIT);
		assertThat(rowCount("user_equipment", owner)).isEqualTo(2);
		assertThat(rowCount("user_equipment", other)).isZero();

		// owner 의 소유 아이템을 other 가 착용할 수는 없다(소유는 사용자별).
		assertThatThrownBy(() -> equip(other, item("HAT", 0, HAT)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.ITEM_NOT_OWNED));
	}
}
