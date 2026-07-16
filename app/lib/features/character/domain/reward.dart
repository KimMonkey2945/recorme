/// 보상 1건(코인 원장 = 리액션 = 보상함 항목). 백엔드 `character_events`의 읽기 모델이다.
///
/// [payload]는 대사·맥락 등을 담은 JSON이며, 표시에 필요한 [line]/[context]만 뽑아 둔다
/// (원본이 필요하면 [payload] 그대로 접근). 보상함 목록과 확정 리액션이 이 타입을 공유한다.
class Reward {
  const Reward({
    required this.id,
    required this.eventType,
    required this.coinDelta,
    required this.createdAt,
    this.balanceAfter,
    this.line,
    this.context,
    this.riveTrigger,
  });

  /// 이벤트 PK(커서 페이징 키).
  final int id;

  /// 적립 종류(DIARY_CONFIRM/RESOLUTION_SUCCESS/RESOLUTION_DAY/STREAK/ATTENDANCE …).
  final String eventType;

  /// 이 이벤트의 코인 변동(적립 +).
  final int coinDelta;

  /// 적립 후 잔액 스냅샷(코인 변동 없으면 null).
  final int? balanceAfter;

  /// 리액션 대사(payload.line). 없을 수 있다.
  final String? line;

  /// 리액션 맥락(payload.context — CONFIRM/STREAK_7/IDLE …).
  final String? context;

  /// 재생 모션 트리거(payload.riveTrigger). 없을 수 있다.
  final String? riveTrigger;

  final DateTime createdAt;
}

/// POST /characters/me/attendance 결과 — 출석 적립.
class AttendanceResult {
  const AttendanceResult({
    required this.granted,
    required this.coin,
    required this.balance,
  });

  /// 이번 호출로 적립됐는지(false = 오늘 이미 출석했거나 출석 보상이 꺼짐).
  final bool granted;

  /// 출석 적립액(기준값).
  final int coin;

  /// 현재 코인 잔액.
  final int balance;
}
