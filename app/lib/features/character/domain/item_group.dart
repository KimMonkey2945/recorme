import 'render_meta.dart';

/// 미션 해금 아이템의 잠금 정보(옷장·상점의 해금 진행률 표시).
///
/// 백엔드 `MissionLockResponse`와 1:1 대응한다.
/// `acquireType=MISSION`이고 아직 미보유일 때만 내려오고, 그 외에는 null이다.
class MissionLock {
  const MissionLock({
    required this.missionCode,
    required this.title,
    required this.progress,
    required this.threshold,
  });

  final String missionCode;
  final String title;
  final int progress;
  final int threshold;
}

/// 아이템 그룹 항목 — 옷장·상점이 공유하는 단일 목록의 원소.
///
/// 백엔드 `GET /characters/items`의 항목과 1:1 대응한다. [owned]로 옷장/상점을 가른다.
/// [imageUrl]·[renderMeta]는 **내 선택 캐릭터 기준으로 해석된 variant**다 —
/// 앱은 variant 개념을 몰라도 된다(소유·착용은 언제나 [groupCode] 단위).
class ItemGroup {
  const ItemGroup({
    required this.groupCode,
    required this.slot,
    required this.nameKo,
    required this.thumbnailUrl,
    required this.acquireType,
    required this.coinPrice,
    required this.owned,
    required this.equipped,
    required this.imageUrl,
    this.renderMeta,
    this.lockedBy,
  });

  final String groupCode;

  /// HAT/OUTFIT/GLASSES/PROP/ROOM_PROP/BACKGROUND.
  final String slot;

  final String nameKo;

  /// 목록 타일용 썸네일(로컬 에셋 경로).
  final String thumbnailUrl;

  /// DEFAULT/MISSION/COIN.
  final String acquireType;

  final int coinPrice;

  final bool owned;

  /// 서버 기준 현재 착용 여부.
  final bool equipped;

  /// 내 캐릭터 기준으로 해석된 렌더 이미지(로컬 에셋 경로).
  final String imageUrl;

  /// 2D 렌더 배치 메타(z가 겹침 순서).
  final RenderMeta? renderMeta;

  /// 미션 해금 잠금 정보(MISSION 미보유일 때만).
  final MissionLock? lockedBy;
}

/// 착용 배치 요청의 항목 1개(`PUT /characters/me/equipment`).
///
/// 배열 전체가 착용 **전체 스냅샷**이 된다(부분 PATCH 아님) — 해제는 배열에서 빼면 된다.
/// [slotIndex]는 단일 슬롯이면 0, ROOM_PROP만 0~5.
class EquipmentSelection {
  const EquipmentSelection({
    required this.slot,
    required this.slotIndex,
    required this.groupCode,
  });

  final String slot;
  final int slotIndex;
  final String groupCode;
}
