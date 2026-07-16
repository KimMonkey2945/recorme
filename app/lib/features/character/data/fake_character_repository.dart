import '../../../core/error/failure.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/character.dart';
import '../domain/character_repository.dart';
import '../domain/equipment_item.dart';
import '../domain/item_group.dart';
import '../domain/my_character.dart';
import '../domain/render_meta.dart';
import '../domain/retrospect.dart';
import '../domain/reward.dart';

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
  /// [ownedGroups]는 테스트가 소유(착용 가능)를, [coinBalance]는 초기 코인을 주입하는 용도다.
  /// 프로덕션 기본은 빈 소유·0코인(5종 전부 잠금 — 구매하려면 코인을 먼저 모아야 한다).
  FakeCharacterRepository({
    String? selectedCode,
    Set<String> ownedGroups = const {},
    int coinBalance = 0,
  })  : _selectedCode = selectedCode,
        _ownedGroups = {...ownedGroups},
        _coinBalance = coinBalance;

  /// 현재 선택된 캐릭터 코드(null이면 미선택 = 온보딩 대상).
  String? _selectedCode;

  /// 현재 착용 스냅샷(slot, slotIndex, groupCode). 서버의 user_equipment에 해당.
  List<EquipmentSelection> _equipment = const [];

  /// 인메모리 코인 잔액(적립 시뮬레이션). 출석/보상으로 늘고, 구매로 준다.
  int _coinBalance;

  /// 미확인 보상함(character_events 미러). ack하면 비워진다.
  final List<Reward> _rewards = [];

  /// 세션 내 출석 완료 여부(하루 1회 시뮬레이션 — Fake는 날짜 없이 세션 단위로 흉내).
  bool _attended = false;

  /// 이미 리액션을 만든 기록 id → 그때의 보상(멱등 — 같은 기록 재진입 시 중복 적립 방지).
  final Map<int, Reward> _reactions = {};

  /// 보상 id 시퀀스.
  int _rewardSeq = 0;

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
  // 옷장 카탈로그 5종(백엔드 V21과 동일). 전부 COIN 구매 대상 — 구매 전까지 미보유(잠금).
  static const _itemGroups = [
    (
      groupCode: 'HAT_CAP_BLACK',
      slot: 'HAT',
      nameKo: '누구나 소화할 수 있는 검은색 캡모자',
      thumbnailUrl: 'assets/items/hat_cap_black.png',
      acquireType: 'COIN',
      coinPrice: 15,
    ),
    (
      groupCode: 'GLASSES_ROUND',
      slot: 'GLASSES',
      nameKo: '안경알은 없지만 멋짐을 위한 검은색 뿔테안경',
      thumbnailUrl: 'assets/items/glasses_round.png',
      acquireType: 'COIN',
      coinPrice: 15,
    ),
    (
      groupCode: 'OUTFIT_LOVE_HOOD',
      slot: 'OUTFIT',
      nameKo: '사랑하는 사람에게 보여주고 싶은 낭낭한 후드티',
      thumbnailUrl: 'assets/items/outfit_love_hood.png',
      acquireType: 'COIN',
      coinPrice: 50,
    ),
    (
      groupCode: 'BOTTOM_CARGO_SAND',
      slot: 'BOTTOM',
      nameKo: '입으면 사막에서도 살아남을 것 같은 바지',
      thumbnailUrl: 'assets/items/bottom_cargo_sand.png',
      acquireType: 'COIN',
      coinPrice: 50,
    ),
    (
      groupCode: 'SHOES_MAX95',
      slot: 'SHOES',
      nameKo: '신발에 에어가 없으면 허리가 아픈 사람을 위한 에어빵빵 신발',
      thumbnailUrl: 'assets/items/shoes_max95.png',
      acquireType: 'COIN',
      coinPrice: 20,
    ),
  ];

  /// variant 시드(백엔드 V21 character_items와 동일). 5종 모두 캐릭터별 2행.
  static const _variants = [
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
  ];

  /// 보유 group 집합. 5종 전부 COIN(구매 대상)이라 기본은 **빈 집합**(전부 잠금)이다.
  /// 구매 기능 구현 전까지 착용 불가이며, 테스트는 생성자 [ownedGroups]로 소유를 주입해 착용 흐름을 검증한다.
  final Set<String> _ownedGroups;

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

  /// group을 내 선택 캐릭터 기준 variant로 해석한다(선택 캐릭터 전용 매칭).
  /// 현재 카탈로그(V21) 5종은 전부 캐릭터별 variant라 공용(character=null) 폴백은 없다
  /// (공용 아이템이 다시 생기면 character==null 폴백을 복원한다).
  ({String imageUrl, ({double anchorX, double anchorY, double scale, int z}) meta})?
      _resolveVariant(String groupCode) {
    for (final v in _variants) {
      if (v.groupCode == groupCode && v.character == _selectedCode) {
        return (imageUrl: v.imageUrl, meta: v.meta);
      }
    }
    return null;
  }

  static RenderMeta _toMeta(
          ({double anchorX, double anchorY, double scale, int z}) meta) =>
      RenderMeta(
        anchorX: meta.anchorX,
        anchorY: meta.anchorY,
        scale: meta.scale,
        z: meta.z,
      );

  @override
  Future<CursorPage<Reward>> fetchRewards({int? cursor, int? size}) async {
    await Future<void>.delayed(_latency);
    final sorted = [..._rewards]..sort((a, b) => b.id.compareTo(a.id));
    final rest = cursor == null
        ? sorted
        : sorted.where((r) => r.id < cursor).toList();
    final page = rest.take(size ?? 20).toList();
    final hasNext = rest.length > page.length;
    return CursorPage(
      items: page,
      nextCursor: page.isEmpty ? null : page.last.id,
      hasNext: hasNext,
    );
  }

  @override
  Future<int> ackRewards() async {
    await Future<void>.delayed(_latency);
    final n = _rewards.length;
    _rewards.clear();
    return n;
  }

  @override
  Future<AttendanceResult> markAttendance() async {
    await Future<void>.delayed(_latency);
    if (_attended) {
      return AttendanceResult(granted: false, coin: 10, balance: _coinBalance);
    }
    _attended = true;
    _coinBalance += 10;
    _rewards.add(Reward(
      id: ++_rewardSeq,
      eventType: 'ATTENDANCE',
      coinDelta: 10,
      balanceAfter: _coinBalance,
      line: '오늘도 왔네, 반가워!',
      context: 'IDLE',
      createdAt: DateTime.now(),
    ));
    return AttendanceResult(granted: true, coin: 10, balance: _coinBalance);
  }

  @override
  Future<MyCharacter> purchaseItem(String groupCode) async {
    await Future<void>.delayed(_latency);
    final matches = _itemGroups.where((g) => g.groupCode == groupCode);
    if (matches.isEmpty) {
      throw const Failure('VALIDATION_ERROR', '구매할 수 없는 아이템이에요.');
    }
    // 이미 보유면 무과금.
    if (_ownedGroups.contains(groupCode)) {
      return _myCharacter();
    }
    final price = matches.first.coinPrice;
    if (_coinBalance < price) {
      throw const Failure('COIN_INSUFFICIENT', '코인이 부족해요.');
    }
    _coinBalance -= price;
    _ownedGroups.add(groupCode);
    return _myCharacter();
  }

  @override
  Future<Reward?> getReaction(int diaryId) async {
    await Future<void>.delayed(_latency);
    // 이미 이 기록의 리액션을 만들었으면 그대로 돌려준다(멱등 — 코인 중복 적립 없음).
    final existing = _reactions[diaryId];
    if (existing != null) return existing;
    // 최초 진입: 확정 보상(코인 +10, CONFIRM 대사)을 시뮬레이션한다.
    _coinBalance += 10;
    final reward = Reward(
      id: ++_rewardSeq,
      eventType: 'DIARY_CONFIRM',
      coinDelta: 10,
      balanceAfter: _coinBalance,
      line: _selectedCode == 'RED_PANDA'
          ? '오늘도 해냈네요! 이 기세로 내일도 꼭 같이 써요.'
          : '오늘도 한 줄 남겼네. 천천히 해도 다 남더라.',
      context: 'CONFIRM',
      createdAt: DateTime.now(),
    );
    _reactions[diaryId] = reward;
    _rewards.add(reward);
    return reward;
  }

  @override
  Future<Retrospect> getRetrospect(String yearMonth) async {
    await Future<void>.delayed(_latency);
    final confirmed = _reactions.length;
    return Retrospect(
      yearMonth: yearMonth,
      confirmedCount: confirmed,
      consecutiveDaysMax: confirmed == 0 ? 0 : (confirmed > 3 ? 3 : confirmed),
      resolutionSuccessCount: 0,
      // 감정 분포는 확정 기록이 있을 때만 흉내낸다(프리셋 + 커스텀 혼재).
      emotions: confirmed == 0
          ? const []
          : const [
              EmotionStat(code: 'JOY', labelKo: '기쁨', count: 2),
              EmotionStat(label: '설레는', count: 1),
            ],
      coinEarned: _coinBalance,
      unlockedItems: [
        for (final code in _ownedGroups)
          UnlockedItem(
            groupCode: code,
            nameKo: _nameOf(code),
            imageUrl: _resolveVariant(code)?.imageUrl,
          ),
      ],
    );
  }

  /// group 코드 → 한국어 이름(카탈로그 조회, 없으면 코드 그대로).
  String _nameOf(String groupCode) {
    for (final g in _itemGroups) {
      if (g.groupCode == groupCode) return g.nameKo;
    }
    return groupCode;
  }

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
      coinBalance: _coinBalance,
      unackedRewardCount: _rewards.length,
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
