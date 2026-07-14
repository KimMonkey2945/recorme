import 'equipment_item.dart';

/// 내가 선택한 캐릭터의 정체성(코드·이름·아트보드·썸네일).
///
/// [riveArtboard]는 Rive 렌더러 전환(Task 031) 시 사용할 아트보드명이다.
/// [thumbnailUrl]은 URL이 아니라 로컬 에셋 경로다.
class SelectedCharacter {
  const SelectedCharacter({
    required this.code,
    required this.nameKo,
    required this.thumbnailUrl,
    this.riveArtboard,
  });

  final String code;
  final String nameKo;

  /// 로컬 에셋 경로(Image.asset으로 로드).
  final String thumbnailUrl;

  /// Rive 아트보드명(비-Rive 렌더러에서는 미사용).
  final String? riveArtboard;
}

/// `GET /characters/me` · `PUT /characters/me/selection` 응답.
///
/// **미선택 사용자도 200으로 응답하며, [character]가 null인 것이 온보딩 신호다(404 아님).**
/// 라우터의 온보딩 리다이렉트 가드는 이 필드만 보고 분기한다.
///
/// 레벨·코인·미확인 보상·장착 아이템은 캐릭터 홈/옷장(Task 029 본편·030) 범위이며,
/// 이번 온보딩 범위에서는 계약만 파싱해 둔다.
class MyCharacter {
  const MyCharacter({
    required this.level,
    required this.exp,
    required this.expToNext,
    required this.coinBalance,
    required this.unackedRewardCount,
    this.character,
    this.equipment = const [],
  });

  /// 선택한 캐릭터. **null이면 아직 선택 전(= 온보딩 필요)**.
  final SelectedCharacter? character;

  final int level;
  final int exp;

  /// 다음 레벨까지 필요한 누적 경험치.
  final int expToNext;

  final int coinBalance;

  /// 아직 확인하지 않은 보상 개수(홈 배지용).
  final int unackedRewardCount;

  /// 현재 장착 중인 아이템 목록.
  final List<EquipmentItem> equipment;

  /// 캐릭터 선택 완료 여부(온보딩 통과 조건).
  bool get hasSelection => character != null;
}
