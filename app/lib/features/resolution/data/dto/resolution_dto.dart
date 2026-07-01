import '../../domain/resolution.dart';

/// 결심 도메인 모델의 JSON 매핑(파싱/직렬화)을 모아 둔 DTO 계층.
///
/// 도메인 모델(`domain/resolution.dart`)은 순수 타입만 갖고, JSON ↔ 도메인 변환은
/// 여기 static 매퍼로 격리한다(계층 분리). 서버 응답 컴포넌트명이 곧 JSON 키다.
class ResolutionDto {
  const ResolutionDto._();

  // ── 응답 파싱(JSON → 도메인) ─────────────────────────────────

  /// ResolutionDetailResponse → [Resolution].
  /// `{id, title, startDate, endDate, status, reminderTime, streakSeq, checks[]}`
  static Resolution fromJson(Map<String, dynamic> json) {
    final rawChecks = json['checks'] as List<dynamic>?;
    return Resolution(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      status: ResolutionStatus.fromApi(json['status'] as String?),
      streakSeq: (json['streakSeq'] as num?)?.toInt() ?? 1,
      // LocalTime은 'HH:mm[:ss]' 문자열로 내려온다(알림 없음이면 null).
      reminderTime: json['reminderTime'] as String?,
      checks: rawChecks == null
          ? const []
          : rawChecks
              .map((e) => checkFromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  /// ResolutionCheckView → [ResolutionCheck].
  /// `{checkDate, dayIndex, status, completedAt}`
  static ResolutionCheck checkFromJson(Map<String, dynamic> json) {
    final completedAt = json['completedAt'] as String?;
    return ResolutionCheck(
      checkDate: DateTime.parse(json['checkDate'] as String),
      dayIndex: (json['dayIndex'] as num).toInt(),
      status: CheckStatus.fromApi(json['status'] as String?),
      // OffsetDateTime ISO 문자열(그 외 null). DONE일 때만 값이 존재한다.
      completedAt:
          (completedAt == null || completedAt.isEmpty) ? null : DateTime.parse(completedAt),
    );
  }

  /// ResolutionListItem → [ResolutionSummaryItem].
  /// `{id, title, startDate, endDate, status, streakSeq, dayStatuses}`
  /// [dayStatuses]는 콤마 문자열("DONE,PENDING,PENDING")이므로 split해 파싱한다.
  static ResolutionSummaryItem summaryFromJson(Map<String, dynamic> json) {
    return ResolutionSummaryItem(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      status: ResolutionStatus.fromApi(json['status'] as String?),
      streakSeq: (json['streakSeq'] as num?)?.toInt() ?? 1,
      dayStatuses: _parseDayStatuses(json['dayStatuses'] as String?),
    );
  }

  /// ResolutionCalendarDay → [ResolutionCalendarDay].
  /// `{date, resolutionId, title, resolutionStatus, checkStatus}`
  static ResolutionCalendarDay calendarDayFromJson(Map<String, dynamic> json) {
    return ResolutionCalendarDay(
      date: DateTime.parse(json['date'] as String),
      resolutionId: (json['resolutionId'] as num).toInt(),
      title: json['title'] as String,
      resolutionStatus: ResolutionStatus.fromApi(json['resolutionStatus'] as String?),
      checkStatus: CheckStatus.fromApi(json['checkStatus'] as String?),
    );
  }

  // ── 요청 직렬화(도메인/입력 → JSON) ───────────────────────────

  /// POST /resolutions 요청 바디.
  /// [reminderTime]은 'HH:mm[:ss]' 문자열(없으면 null → 알림 없음).
  static Map<String, dynamic> createRequest({
    required String title,
    required DateTime startDate,
    String? reminderTime,
  }) =>
      {
        'title': title,
        'startDate': yyyyMMdd(startDate),
        'reminderTime': reminderTime,
      };

  /// POST /resolutions/{id}/extend 요청 바디.
  /// [reminderTime]이 null이면 이전 결심의 알림 시각을 승계한다(서버 처리).
  static Map<String, dynamic> extendRequest({String? reminderTime}) => {
        'reminderTime': reminderTime,
      };

  // ── 유틸 ────────────────────────────────────────────────────

  /// 콤마 문자열("DONE,PENDING,PENDING")을 [CheckStatus] 리스트로 분해한다.
  /// null·빈 문자열은 빈 리스트로 처리한다.
  static List<CheckStatus> _parseDayStatuses(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((s) => CheckStatus.fromApi(s.trim()))
        .toList();
  }

  /// 날짜를 'yyyy-MM-dd'(zero-pad)로 변환한다. 시간 정보는 버린다.
  static String yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
