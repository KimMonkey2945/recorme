import '../../../../shared/models/cursor_page.dart';
import '../../domain/character.dart';
import '../../domain/equipment_item.dart';
import '../../domain/item_group.dart';
import '../../domain/my_character.dart';
import '../../domain/render_meta.dart';
import '../../domain/retrospect.dart';
import '../../domain/reward.dart';

/// 캐릭터 도메인 모델의 JSON 매핑(파싱/직렬화)을 모아 둔 DTO 계층.
///
/// 도메인 모델(`domain/*.dart`)은 순수 타입만 갖고, JSON ↔ 도메인 변환은
/// 여기 static 매퍼로 격리한다(계층 분리). 서버 응답 컴포넌트명이 곧 JSON 키다.
class CharacterDto {
  const CharacterDto._();

  // ── 응답 파싱(JSON → 도메인) ─────────────────────────────────

  /// CharacterListResponse → [CharacterList].
  /// `{selectedCharacter, items[]}`
  static CharacterList listFromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>?;
    return CharacterList(
      selectedCharacter: json['selectedCharacter'] as String?,
      items: rawItems == null
          ? const []
          : rawItems
              .map((e) => characterFromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  /// CharacterItem → [Character].
  /// `{code, nameKo, tagline, thumbnailUrl, owned, selected}`
  static Character characterFromJson(Map<String, dynamic> json) => Character(
        code: json['code'] as String,
        nameKo: json['nameKo'] as String? ?? '',
        tagline: json['tagline'] as String? ?? '',
        // 로컬 에셋 경로('assets/characters/monkey.png')다. URL이 아니다.
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        owned: json['owned'] as bool? ?? false,
        selected: json['selected'] as bool? ?? false,
      );

  /// MyCharacterResponse → [MyCharacter].
  /// `{character, level, exp, expToNext, coinBalance, unackedRewardCount, equipment[]}`
  /// **`character`는 미선택자면 null이다(온보딩 신호).**
  static MyCharacter myCharacterFromJson(Map<String, dynamic> json) {
    final rawCharacter = json['character'] as Map<String, dynamic>?;
    final rawEquipment = json['equipment'] as List<dynamic>?;
    return MyCharacter(
      character:
          rawCharacter == null ? null : selectedCharacterFromJson(rawCharacter),
      coinBalance: (json['coinBalance'] as num?)?.toInt() ?? 0,
      unackedRewardCount: (json['unackedRewardCount'] as num?)?.toInt() ?? 0,
      equipment: rawEquipment == null
          ? const []
          : rawEquipment
              .map((e) => equipmentFromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  /// MyCharacterResponse.character → [SelectedCharacter].
  /// `{code, nameKo, riveArtboard, thumbnailUrl}`
  static SelectedCharacter selectedCharacterFromJson(Map<String, dynamic> json) =>
      SelectedCharacter(
        code: json['code'] as String,
        nameKo: json['nameKo'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        riveArtboard: json['riveArtboard'] as String?,
      );

  /// EquipmentView → [EquipmentItem].
  /// `{slot, slotIndex, groupCode, nameKo, imageUrl, riveSlot, renderMeta}`
  static EquipmentItem equipmentFromJson(Map<String, dynamic> json) {
    final rawMeta = json['renderMeta'] as Map<String, dynamic>?;
    return EquipmentItem(
      slot: json['slot'] as String? ?? '',
      slotIndex: (json['slotIndex'] as num?)?.toInt() ?? 0,
      groupCode: json['groupCode'] as String? ?? '',
      nameKo: json['nameKo'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      riveSlot: json['riveSlot'] as String?,
      renderMeta: rawMeta == null ? null : renderMetaFromJson(rawMeta),
    );
  }

  /// renderMeta → [RenderMeta].
  /// `{anchorX, anchorY, scale, z}`
  static RenderMeta renderMetaFromJson(Map<String, dynamic> json) => RenderMeta(
        anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0.5,
        anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0.5,
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
        z: (json['z'] as num?)?.toInt() ?? 0,
      );

  /// ItemGroupListResponse → [List<ItemGroup>].
  /// `{items[]}`
  static List<ItemGroup> itemGroupsFromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>?;
    return rawItems == null
        ? const []
        : rawItems
            .map((e) => itemGroupFromJson(e as Map<String, dynamic>))
            .toList();
  }

  /// ItemGroupResponse → [ItemGroup].
  /// `{groupCode, slot, nameKo, thumbnailUrl, acquireType, coinPrice,
  ///   owned, equipped, imageUrl, renderMeta, lockedBy}`
  static ItemGroup itemGroupFromJson(Map<String, dynamic> json) {
    final rawMeta = json['renderMeta'] as Map<String, dynamic>?;
    final rawLock = json['lockedBy'] as Map<String, dynamic>?;
    return ItemGroup(
      groupCode: json['groupCode'] as String? ?? '',
      slot: json['slot'] as String? ?? '',
      nameKo: json['nameKo'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      acquireType: json['acquireType'] as String? ?? '',
      coinPrice: (json['coinPrice'] as num?)?.toInt() ?? 0,
      owned: json['owned'] as bool? ?? false,
      equipped: json['equipped'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String? ?? '',
      renderMeta: rawMeta == null ? null : renderMetaFromJson(rawMeta),
      lockedBy: rawLock == null ? null : missionLockFromJson(rawLock),
    );
  }

  /// MissionLockResponse → [MissionLock].
  /// `{missionCode, title, progress, threshold}`
  static MissionLock missionLockFromJson(Map<String, dynamic> json) =>
      MissionLock(
        missionCode: json['missionCode'] as String? ?? '',
        title: json['title'] as String? ?? '',
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        threshold: (json['threshold'] as num?)?.toInt() ?? 0,
      );

  /// RewardResponse → [Reward].
  /// `{id, eventType, coinDelta, balanceAfter, payload:{context,coin,balance,line,riveTrigger}, createdAt}`
  static Reward rewardFromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>?;
    return Reward(
      id: (json['id'] as num).toInt(),
      eventType: json['eventType'] as String? ?? '',
      coinDelta: (json['coinDelta'] as num?)?.toInt() ?? 0,
      balanceAfter: (json['balanceAfter'] as num?)?.toInt(),
      line: payload?['line'] as String?,
      context: payload?['context'] as String?,
      riveTrigger: payload?['riveTrigger'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// PageResponse(RewardResponse) → `CursorPage<Reward>`.
  static CursorPage<Reward> rewardsPageFromJson(Map<String, dynamic> json) =>
      CursorPage<Reward>.fromJson(
        json,
        (e) => rewardFromJson(e as Map<String, dynamic>),
      );

  /// AttendanceResponse → [AttendanceResult].
  /// `{granted, coin, balance}`
  static AttendanceResult attendanceFromJson(Map<String, dynamic> json) =>
      AttendanceResult(
        granted: json['granted'] as bool? ?? false,
        coin: (json['coin'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
      );

  /// RetrospectResponse → [Retrospect].
  /// `{yearMonth, confirmedCount, consecutiveDaysMax, resolutionSuccessCount,
  ///   emotions[], coinEarned, unlockedItems[]}`
  static Retrospect retrospectFromJson(Map<String, dynamic> json) {
    final rawEmotions = json['emotions'] as List<dynamic>?;
    final rawItems = json['unlockedItems'] as List<dynamic>?;
    return Retrospect(
      yearMonth: json['yearMonth'] as String? ?? '',
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
      consecutiveDaysMax: (json['consecutiveDaysMax'] as num?)?.toInt() ?? 0,
      resolutionSuccessCount:
          (json['resolutionSuccessCount'] as num?)?.toInt() ?? 0,
      coinEarned: (json['coinEarned'] as num?)?.toInt() ?? 0,
      emotions: rawEmotions == null
          ? const []
          : rawEmotions
              .map((e) => emotionStatFromJson(e as Map<String, dynamic>))
              .toList(),
      unlockedItems: rawItems == null
          ? const []
          : rawItems
              .map((e) => unlockedItemFromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  /// EmotionStat → [EmotionStat].
  /// 프리셋은 `{code, labelKo, count}`, 직접 입력은 `{label, count}`(NON_NULL 직렬화라 키가 갈린다).
  static EmotionStat emotionStatFromJson(Map<String, dynamic> json) =>
      EmotionStat(
        code: json['code'] as String?,
        labelKo: json['labelKo'] as String?,
        label: json['label'] as String?,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  /// UnlockedItem → [UnlockedItem].
  /// `{groupCode, nameKo, imageUrl?}`
  static UnlockedItem unlockedItemFromJson(Map<String, dynamic> json) =>
      UnlockedItem(
        groupCode: json['groupCode'] as String? ?? '',
        nameKo: json['nameKo'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
      );

  // ── 요청 직렬화(입력 → JSON) ─────────────────────────────────

  /// PUT /characters/me/selection 요청 바디.
  static Map<String, dynamic> selectionRequest(String characterCode) => {
        'characterCode': characterCode,
      };

  /// PUT /characters/me/equipment 요청 바디(착용 전체 스냅샷).
  static Map<String, dynamic> equipmentRequest(
          List<EquipmentSelection> equipment) =>
      {
        'equipment': [
          for (final e in equipment)
            {
              'slot': e.slot,
              'slotIndex': e.slotIndex,
              'groupCode': e.groupCode,
            },
        ],
      };
}
