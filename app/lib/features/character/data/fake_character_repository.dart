import '../../../core/error/failure.dart';
import '../domain/character.dart';
import '../domain/character_repository.dart';
import '../domain/equipment_item.dart';
import '../domain/item_group.dart';
import '../domain/my_character.dart';
import '../domain/render_meta.dart';

/// 인메모리 더미 캐릭터 저장소(테스트/웹 프리뷰용).
///
/// 실제 백엔드 없이 목록 조회·내 캐릭터 조회·선택·옷장(아이템 목록·착용 배치)을 시뮬레이션한다.
/// `--dart-define=USE_FAKE_CHARACTER_REPO=true`로 켜면 웹(`flutter run -d chrome`)에서
/// 백엔드 없이 온보딩·옷장 화면을 그대로 확인할 수 있다.
/// 실제 환경에서는 이 클래스만 [ApiCharacterRepository]로 교체하면 화면 코드는 그대로 동작한다.
/// (FakeResolutionRepository 스타일을 미러링한다.)
///
/// 아이템 카탈로그는 백엔드 시드(V15)와 동일하다: group(소유·착용) ↔ variant(렌더) 2단 구조를
/// 흉내 내어, 렌더 이미지는 `(group + 선택 캐릭터)`로 해석한다.
class FakeCharacterRepository implements CharacterRepository {
  FakeCharacterRepository({String? selectedCode}) : _selectedCode = selectedCode;

  /// 현재 선택된 캐릭터 코드(null이면 미선택 = 온보딩 대상).
  String? _selectedCode;

  /// 현재 착용 스냅샷(slot, slotIndex, groupCode). 서버의 user_equipment에 해당.
  List<EquipmentSelection> _equipment = const [];

  /// 네트워크 지연 흉내.
  static const _latency = Duration(milliseconds: 300);

  /// 백엔드 시드(V15)와 동일한 2종. 썸네일은 로컬 에셋 경로다.
  static const _catalog = [
    (
      code: 'MONKEY',
      nameKo: '원숭이',
      tagline: '뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.',
      thumbnailUrl: 'assets/characters/monkey.png',
      riveArtboard: 'monkey',
    ),
    (
      code: 'RED_PANDA',
      nameKo: '레서판다',
      tagline: '부지런히 곁을 지켜요. 정 많고 애착이 강한 친구예요.',
      thumbnailUrl: 'assets/characters/red_panda.png',
      riveArtboard: 'red_panda',
    ),
  ];

  /// 아이템 그룹 시드(V15 item_groups와 동일). DEFAULT만 기본 보유다.
  static const _itemGroups = [
    (
      groupCode: 'OUTFIT_BASIC_TEE',
      slot: 'OUTFIT',
      nameKo: '기본 흰 티셔츠',
      thumbnailUrl: 'assets/items/outfit_basic_tee.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
    (
      groupCode: 'ROOM_PROP_PLANT',
      slot: 'ROOM_PROP',
      nameKo: '작은 화분',
      thumbnailUrl: 'assets/items/room_prop_plant.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
    (
      groupCode: 'HAT_CAP_EMIS',
      slot: 'HAT',
      nameKo: '이미스 볼캡',
      thumbnailUrl: 'assets/items/hat_cap_emis.png',
      acquireType: 'MISSION',
      coinPrice: 0,
    ),
    (
      groupCode: 'BG_COZY_ROOM',
      slot: 'BACKGROUND',
      nameKo: '아늑한 방',
      thumbnailUrl: 'assets/items/bg_cozy_room.png',
      acquireType: 'MISSION',
      coinPrice: 0,
    ),
    (
      groupCode: 'HAT_STRAW',
      slot: 'HAT',
      nameKo: '밀짚모자',
      thumbnailUrl: 'assets/items/hat_straw.png',
      acquireType: 'COIN',
      coinPrice: 120,
    ),
    // ── 실사 에셋 파이프라인 검증용 3종(2026-07-15, docs/recormeImo/item 원본) ──
    (
      groupCode: 'HAT_CAP_BLACK',
      slot: 'HAT',
      nameKo: '검정 볼캡',
      thumbnailUrl: 'assets/items/hat_cap_black.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
    (
      groupCode: 'GLASSES_ROUND',
      slot: 'GLASSES',
      nameKo: '둥근 뿔테 안경',
      thumbnailUrl: 'assets/items/glasses_round.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
    (
      groupCode: 'OUTFIT_LOVE_SET',
      slot: 'OUTFIT',
      nameKo: '러브 풀룩 세트',
      thumbnailUrl: 'assets/items/outfit_love_set.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
    // ── 부위별 개별 아이템(2026-07-15, wearItem diff 추출 — 아직 원숭이 착용샷만 있음) ──
    (
      groupCode: 'OUTFIT_LOVE_HOOD',
      slot: 'OUTFIT',
      nameKo: '러브 후드',
      thumbnailUrl: 'assets/items/outfit_love_hood.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
    (
      groupCode: 'BOTTOM_CARGO_SAND',
      slot: 'BOTTOM',
      nameKo: '샌드 카고 팬츠',
      thumbnailUrl: 'assets/items/bottom_cargo_sand.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
    (
      groupCode: 'SHOES_MAX95',
      slot: 'SHOES',
      nameKo: '맥스 95 민트',
      thumbnailUrl: 'assets/items/shoes_max95.png',
      acquireType: 'DEFAULT',
      coinPrice: 0,
    ),
  ];

  /// variant 시드(V15 character_items와 동일).
  /// 착용형은 캐릭터별 2행, 공용(ROOM_PROP/BACKGROUND)은 character=null 1행.
  static const _variants = [
    (
      groupCode: 'OUTFIT_BASIC_TEE',
      character: 'MONKEY',
      imageUrl: 'assets/items/outfit_basic_tee_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.55, scale: 0.60, z: 30),
    ),
    (
      groupCode: 'OUTFIT_BASIC_TEE',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/outfit_basic_tee_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.58, scale: 0.66, z: 30),
    ),
    (
      groupCode: 'HAT_CAP_EMIS',
      character: 'MONKEY',
      imageUrl: 'assets/items/hat_cap_emis_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.18, scale: 0.42, z: 40),
    ),
    (
      groupCode: 'HAT_CAP_EMIS',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/hat_cap_emis_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.16, scale: 0.48, z: 40),
    ),
    (
      groupCode: 'HAT_STRAW',
      character: 'MONKEY',
      imageUrl: 'assets/items/hat_straw_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.18, scale: 0.44, z: 40),
    ),
    (
      groupCode: 'HAT_STRAW',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/hat_straw_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.16, scale: 0.50, z: 40),
    ),
    (
      groupCode: 'HAT_CAP_BLACK',
      character: 'MONKEY',
      imageUrl: 'assets/items/hat_cap_black_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.18, scale: 0.42, z: 40),
    ),
    (
      groupCode: 'HAT_CAP_BLACK',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/hat_cap_black_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.16, scale: 0.48, z: 40),
    ),
    (
      groupCode: 'GLASSES_ROUND',
      character: 'MONKEY',
      imageUrl: 'assets/items/glasses_round_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.27, scale: 0.40, z: 35),
    ),
    (
      groupCode: 'GLASSES_ROUND',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/glasses_round_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.26, scale: 0.42, z: 35),
    ),
    (
      groupCode: 'OUTFIT_LOVE_SET',
      character: 'MONKEY',
      imageUrl: 'assets/items/outfit_love_set_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.62, scale: 0.80, z: 30),
    ),
    (
      groupCode: 'OUTFIT_LOVE_SET',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/outfit_love_set_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.62, scale: 0.92, z: 30),
    ),
    // 의류 3종: 공용 공유는 판다 검증에서 기각(원숭이 픽셀 조각 노출) → 캐릭터별 variant.
    (
      groupCode: 'OUTFIT_LOVE_HOOD',
      character: 'MONKEY',
      imageUrl: 'assets/items/outfit_love_hood_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.6, scale: 0.8, z: 30),
    ),
    (
      groupCode: 'OUTFIT_LOVE_HOOD',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/outfit_love_hood_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.6, scale: 0.8, z: 30),
    ),
    (
      groupCode: 'BOTTOM_CARGO_SAND',
      character: 'MONKEY',
      imageUrl: 'assets/items/bottom_cargo_sand_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.75, scale: 0.6, z: 28),
    ),
    (
      groupCode: 'BOTTOM_CARGO_SAND',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/bottom_cargo_sand_red_panda.png',
      meta: (anchorX: 0.5, anchorY: 0.75, scale: 0.6, z: 28),
    ),
    (
      groupCode: 'SHOES_MAX95',
      character: 'MONKEY',
      imageUrl: 'assets/items/shoes_max95_monkey.png',
      meta: (anchorX: 0.5, anchorY: 0.93, scale: 0.5, z: 26),
    ),
    (
      groupCode: 'SHOES_MAX95',
      character: 'RED_PANDA',
      imageUrl: 'assets/items/shoes_max95_red_panda.png',
      // 판다는 하의가 "하반신 영역 통째 교체"(맨발 포함)라서 신발을 그 위(z 29)에 그린다.
      meta: (anchorX: 0.5, anchorY: 0.93, scale: 0.5, z: 29),
    ),
    (
      groupCode: 'ROOM_PROP_PLANT',
      character: null,
      imageUrl: 'assets/items/room_prop_plant.png',
      meta: (anchorX: 0.82, anchorY: 0.78, scale: 0.30, z: 10),
    ),
    (
      groupCode: 'BG_COZY_ROOM',
      character: null,
      imageUrl: 'assets/items/bg_cozy_room.png',
      meta: (anchorX: 0.5, anchorY: 0.5, scale: 1.0, z: 0),
    ),
  ];

  /// 보유 group 집합. 시드 규칙과 동일하게 DEFAULT만 기본 보유이며,
  /// 프리뷰에서 옷장을 채워 볼 수 있도록 미션 보상(HAT_CAP_EMIS)도 보유로 둔다.
  final Set<String> _ownedGroups = {
    'OUTFIT_BASIC_TEE',
    'ROOM_PROP_PLANT',
    'HAT_CAP_EMIS',
    'HAT_CAP_BLACK',
    'GLASSES_ROUND',
    'OUTFIT_LOVE_SET',
    'OUTFIT_LOVE_HOOD',
    'BOTTOM_CARGO_SAND',
    'SHOES_MAX95',
  };

  @override
  Future<CharacterList> fetchCharacters() async {
    await Future<void>.delayed(_latency);
    return CharacterList(
      selectedCharacter: _selectedCode,
      items: [
        for (final c in _catalog)
          Character(
            code: c.code,
            nameKo: c.nameKo,
            tagline: c.tagline,
            thumbnailUrl: c.thumbnailUrl,
            // 기본 2종은 모두 보유 상태다.
            owned: true,
            selected: c.code == _selectedCode,
          ),
      ],
    );
  }

  @override
  Future<MyCharacter> fetchMyCharacter() async {
    await Future<void>.delayed(_latency);
    return _myCharacter();
  }

  @override
  Future<MyCharacter> selectCharacter(String code) async {
    await Future<void>.delayed(_latency);
    final owned = _catalog.any((c) => c.code == code);
    if (!owned) {
      throw const Failure('CHARACTER_NOT_OWNED', '아직 보유하지 않은 캐릭터예요.');
    }
    _selectedCode = code;
    return _myCharacter();
  }

  @override
  Future<List<ItemGroup>> fetchItems({String? slot}) async {
    await Future<void>.delayed(_latency);
    final equippedCodes = {for (final e in _equipment) e.groupCode};
    final result = <ItemGroup>[];
    for (final g in _itemGroups) {
      if (slot != null && g.slot != slot) continue;
      final variant = _resolveVariant(g.groupCode);
      // 내 캐릭터용 variant가 없는 그룹은 목록에서 제외(백엔드와 동일 규칙).
      if (variant == null) continue;
      final owned = _ownedGroups.contains(g.groupCode);
      result.add(ItemGroup(
        groupCode: g.groupCode,
        slot: g.slot,
        nameKo: g.nameKo,
        thumbnailUrl: g.thumbnailUrl,
        acquireType: g.acquireType,
        coinPrice: g.coinPrice,
        owned: owned,
        equipped: equippedCodes.contains(g.groupCode),
        imageUrl: variant.imageUrl,
        renderMeta: _toMeta(variant.meta),
        lockedBy: g.acquireType == 'MISSION' && !owned
            ? const MissionLock(
                missionCode: 'RECORD_10',
                title: '기록 10개 쓰기',
                progress: 7,
                threshold: 10,
              )
            : null,
      ));
    }
    return result;
  }

  @override
  Future<MyCharacter> replaceEquipment(
      List<EquipmentSelection> equipment) async {
    await Future<void>.delayed(_latency);
    // 검증 전부 통과 시에만 반영(백엔드의 원자적 DELETE→INSERT와 동일 의미).
    for (final e in equipment) {
      if (!_ownedGroups.contains(e.groupCode)) {
        throw const Failure('ITEM_NOT_OWNED', '아직 보유하지 않은 아이템이에요.');
      }
      if (_resolveVariant(e.groupCode) == null) {
        throw const Failure(
            'ITEM_VARIANT_MISSING', '이 캐릭터용 이미지가 아직 준비되지 않았어요.');
      }
    }
    _equipment = List.of(equipment);
    return _myCharacter();
  }

  // ── 유틸 ────────────────────────────────────────────────────

  /// group을 내 선택 캐릭터 기준 variant로 해석한다(전용 우선 → 공용 폴백).
  ({String imageUrl, ({double anchorX, double anchorY, double scale, int z}) meta})?
      _resolveVariant(String groupCode) {
    ({String imageUrl, ({double anchorX, double anchorY, double scale, int z}) meta})?
        common;
    for (final v in _variants) {
      if (v.groupCode != groupCode) continue;
      if (v.character == _selectedCode) {
        return (imageUrl: v.imageUrl, meta: v.meta);
      }
      if (v.character == null) common = (imageUrl: v.imageUrl, meta: v.meta);
    }
    return common;
  }

  static RenderMeta _toMeta(
          ({double anchorX, double anchorY, double scale, int z}) meta) =>
      RenderMeta(
        anchorX: meta.anchorX,
        anchorY: meta.anchorY,
        scale: meta.scale,
        z: meta.z,
      );

  /// 현재 선택 상태 기준의 내 캐릭터 응답을 만든다(미선택이면 character=null).
  MyCharacter _myCharacter() {
    final selected = _selectedCode;
    final matches = _catalog.where((c) => c.code == selected);
    final entry = matches.isEmpty ? null : matches.first;
    return MyCharacter(
      character: entry == null
          ? null
          : SelectedCharacter(
              code: entry.code,
              nameKo: entry.nameKo,
              thumbnailUrl: entry.thumbnailUrl,
              riveArtboard: entry.riveArtboard,
            ),
      coinBalance: 0,
      unackedRewardCount: 0,
      equipment: _equipmentItems(),
    );
  }

  /// 착용 스냅샷을 내 캐릭터 기준 variant로 해석한 [EquipmentItem] 목록.
  List<EquipmentItem> _equipmentItems() {
    final items = <EquipmentItem>[];
    for (final e in _equipment) {
      final matches = _itemGroups.where((g) => g.groupCode == e.groupCode);
      final group = matches.isEmpty ? null : matches.first;
      final variant = _resolveVariant(e.groupCode);
      if (group == null || variant == null) continue;
      items.add(EquipmentItem(
        slot: e.slot,
        slotIndex: e.slotIndex,
        groupCode: e.groupCode,
        nameKo: group.nameKo,
        imageUrl: variant.imageUrl,
        renderMeta: _toMeta(variant.meta),
      ));
    }
    return items;
  }
}
