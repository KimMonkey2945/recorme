/// 월간 회고(Task 032 — 락인). 백엔드 `GET /characters/me/retrospect`의 읽기 모델이다.
///
/// 이달의 기록·연속일·감정 분포·획득 코인·획득 아이템을 한 장에 담는다. 성장 지표는
/// 코인([coinEarned])·획득 아이템([unlockedItems])으로만 표현한다(경험치/레벨은 폐기).
/// 빈 달(기록 0건)도 모든 수치 0 + 빈 리스트로 정상적으로 온다.
class Retrospect {
  const Retrospect({
    required this.yearMonth,
    required this.confirmedCount,
    required this.consecutiveDaysMax,
    required this.resolutionSuccessCount,
    required this.emotions,
    required this.coinEarned,
    required this.unlockedItems,
  });

  /// 대상 월(YYYY-MM).
  final String yearMonth;

  /// 이달 확정 기록 수.
  final int confirmedCount;

  /// 이달 안에서의 최장 연속 기록일.
  final int consecutiveDaysMax;

  /// 이달 작심삼일 완주 수.
  final int resolutionSuccessCount;

  /// 감정 분포(프리셋 + 직접 입력 라벨 혼재, 많은 순). 감정 미입력 기록은 집계에서 빠진다.
  final List<EmotionStat> emotions;

  /// 이달 획득 코인 합(구매 소비 제외).
  final int coinEarned;

  /// 이달 획득(구매·해금)한 아이템(내 캐릭터 기준 이미지).
  final List<UnlockedItem> unlockedItems;
}

/// 월간 감정 분포 1건. 프리셋(코드 존재)과 직접 입력(라벨만)이 섞여 온다.
class EmotionStat {
  const EmotionStat({
    this.code,
    this.labelKo,
    this.label,
    required this.count,
  });

  /// 프리셋 감정 코드(직접 입력이면 null).
  final String? code;

  /// 프리셋 한국어 라벨(직접 입력이면 null).
  final String? labelKo;

  /// 직접 입력 감정 텍스트(프리셋이면 null).
  final String? label;

  /// 해당 감정으로 확정한 기록 수.
  final int count;

  /// 프리셋 감정인지(코드가 있으면 프리셋).
  bool get isPreset => code != null && code!.isNotEmpty;

  /// 화면 표시 라벨 — 프리셋이면 한국어 라벨, 직접 입력이면 자유 텍스트.
  String get displayLabel =>
      isPreset ? (labelKo ?? code!) : (label ?? '감정');
}

/// 이달 획득 아이템 1건.
class UnlockedItem {
  const UnlockedItem({
    required this.groupCode,
    required this.nameKo,
    this.imageUrl,
  });

  /// 아이템 group 코드.
  final String groupCode;

  /// 아이템 한국어 이름.
  final String nameKo;

  /// 내 캐릭터 기준 렌더 이미지(로컬 에셋 경로). 해석 실패 시 null.
  final String? imageUrl;
}
