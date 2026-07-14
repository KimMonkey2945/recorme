import 'render_meta.dart';

/// 현재 장착 중인 아이템 1개.
///
/// 백엔드 `GET /characters/me`의 `equipment[]` 항목과 1:1 대응한다.
/// [imageUrl]은 URL이 아니라 로컬 에셋 경로('assets/items/...')다.
/// [riveSlot]은 Rive 렌더러 전환(Task 031) 시 사용할 슬롯명이다.
///
/// 옷장·상점 UI는 이번 범위가 아니며(Task 030), 여기서는 계약만 파싱해 둔다.
class EquipmentItem {
  const EquipmentItem({
    required this.slot,
    required this.slotIndex,
    required this.groupCode,
    required this.nameKo,
    required this.imageUrl,
    this.riveSlot,
    this.renderMeta,
  });

  /// 장착 슬롯(OUTFIT/HAT/...). 서버 문자열 그대로 보관한다.
  final String slot;

  /// 같은 슬롯 내 순번(0부터).
  final int slotIndex;

  /// 아이템 그룹 코드(OUTFIT_BASIC_TEE 등).
  final String groupCode;

  /// 표시용 한국어 이름.
  final String nameKo;

  /// 로컬 에셋 경로(Image.asset으로 로드).
  final String imageUrl;

  /// Rive 아트보드의 슬롯명(비-Rive 렌더러에서는 미사용).
  final String? riveSlot;

  /// 2D 폴백 렌더러용 배치 메타(없을 수 있음).
  final RenderMeta? renderMeta;
}
