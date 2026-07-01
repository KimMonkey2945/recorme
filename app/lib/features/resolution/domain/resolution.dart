import 'package:flutter/material.dart' show TimeOfDay;

/// 작심삼일(결심) 도메인 모델.
///
/// 백엔드 `resolution` 도메인 응답과 1:1 대응한다. JSON 파싱은 데이터 계층
/// (`data/dto/resolution_dto.dart`)이 담당하고, 여기에는 순수 도메인 타입만 둔다.
/// (diary 도메인의 순수성 관례를 따른다.)

/// 결심의 진행 상태. 서버 문자열(대문자)과 1:1 매핑한다.
///
/// - [ongoing]: 진행 중(3일 도전 중)
/// - [success]: 3일 모두 완료
/// - [failed]: 중간에 놓쳐 실패
/// - [unknown]: 서버가 미지의 값을 보냈을 때의 안전 폴백
enum ResolutionStatus {
  ongoing,
  success,
  failed,
  unknown;

  /// 서버 문자열(ONGOING/SUCCESS/FAILED) → enum. 미지값·null은 [unknown] 폴백.
  static ResolutionStatus fromApi(String? raw) {
    switch (raw) {
      case 'ONGOING':
        return ResolutionStatus.ongoing;
      case 'SUCCESS':
        return ResolutionStatus.success;
      case 'FAILED':
        return ResolutionStatus.failed;
      default:
        return ResolutionStatus.unknown;
    }
  }

  /// enum → 서버 문자열(목록 필터 쿼리 파라미터용).
  /// [unknown]은 null을 돌려줘 필터를 적용하지 않는다.
  String? get apiValue {
    switch (this) {
      case ResolutionStatus.ongoing:
        return 'ONGOING';
      case ResolutionStatus.success:
        return 'SUCCESS';
      case ResolutionStatus.failed:
        return 'FAILED';
      case ResolutionStatus.unknown:
        return null;
    }
  }
}

/// 하루치 체크의 상태. 서버 문자열(대문자)과 1:1 매핑한다.
///
/// - [pending]: 아직 완료하지 않음(오늘/미래)
/// - [done]: 완료 체크됨
/// - [missed]: 그 날짜를 놓침(실패 확정)
/// - [unknown]: 서버가 미지의 값을 보냈을 때의 안전 폴백
enum CheckStatus {
  pending,
  done,
  missed,
  unknown;

  /// 서버 문자열(PENDING/DONE/MISSED) → enum. 미지값·null은 [unknown] 폴백.
  static CheckStatus fromApi(String? raw) {
    switch (raw) {
      case 'PENDING':
        return CheckStatus.pending;
      case 'DONE':
        return CheckStatus.done;
      case 'MISSED':
        return CheckStatus.missed;
      default:
        return CheckStatus.unknown;
    }
  }
}

/// 결심의 하루치 체크(1·2·3일차 각 1행).
///
/// [completedAt]은 [CheckStatus.done] 전이 시각이며, PENDING/MISSED면 null이다.
class ResolutionCheck {
  const ResolutionCheck({
    required this.checkDate,
    required this.dayIndex,
    required this.status,
    this.completedAt,
  });

  /// 체크 대상 날짜(시작일 + (dayIndex-1)).
  final DateTime checkDate;

  /// 1·2·3일차 순번(1부터).
  final int dayIndex;

  /// 이 날짜 체크의 상태.
  final CheckStatus status;

  /// DONE 전이 시각(그 외 null).
  final DateTime? completedAt;

  /// 완료 체크 여부.
  bool get isDone => status == CheckStatus.done;
}

/// 결심 단건(상세 화면용). 헤더(제목·기간·상태·알림·연속 순번)와 3일치 체크를 함께 담는다.
///
/// [reminderTime]은 매일 알림 벽시계 시각('HH:mm' 또는 'HH:mm:ss' 문자열)이며
/// null이면 알림 없음이다. UI에서는 [reminderTimeOfDay]로 [TimeOfDay]를 얻는다.
/// [streakSeq]는 연장 체인 내 순번(1부터, "N연속")이다.
class Resolution {
  const Resolution({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.streakSeq,
    this.reminderTime,
    this.checks = const [],
  });

  final int id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final ResolutionStatus status;

  /// 연장 체인 내 순번(1부터). 1이면 최초, 2 이상이면 "N연속".
  final int streakSeq;

  /// 매일 알림 시각 문자열('HH:mm' 또는 'HH:mm:ss'). null이면 알림 없음.
  final String? reminderTime;

  /// day_index 오름차순 1·2·3일차 체크.
  final List<ResolutionCheck> checks;

  // ── 편의 getter ──────────────────────────────────────────────

  /// 진행 중 여부.
  bool get isOngoing => status == ResolutionStatus.ongoing;

  /// 3일 도전을 모두 성공했는지 여부(연장 가능 조건).
  bool get isSuccess => status == ResolutionStatus.success;

  /// 알림 시각을 [TimeOfDay]로 변환한다. 없거나 파싱 불가면 null.
  TimeOfDay? get reminderTimeOfDay {
    final raw = reminderTime;
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }
}

/// 결심 목록 항목(진행/성공/실패 탭 + 최신순 커서용 경량 모델).
///
/// 상세의 체크 컬렉션 대신, 3일 진행 도트 렌더용으로 [dayStatuses](day_index 순
/// 체크 상태 리스트)만 얇게 싣는다. 서버는 이를 콤마 문자열("DONE,PENDING,PENDING")로
/// 내려주며, DTO 계층이 split해 이 리스트로 파싱한다.
class ResolutionSummaryItem {
  const ResolutionSummaryItem({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.streakSeq,
    this.dayStatuses = const [],
  });

  final int id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final ResolutionStatus status;
  final int streakSeq;

  /// 1·2·3일차 체크 상태(콤마 문자열을 분해해 파싱). 최대 3개.
  final List<CheckStatus> dayStatuses;
}

/// 월별 캘린더의 한 칸((날짜 × 결심)당 1행).
///
/// 하루에 여러 결심이 진행될 수 있어 (날짜, 결심)당 1행이다.
/// [resolutionStatus]는 소속 결심 상태, [checkStatus]는 그 날짜 체크 상태다.
class ResolutionCalendarDay {
  const ResolutionCalendarDay({
    required this.date,
    required this.resolutionId,
    required this.title,
    required this.resolutionStatus,
    required this.checkStatus,
  });

  final DateTime date;
  final int resolutionId;
  final String title;
  final ResolutionStatus resolutionStatus;
  final CheckStatus checkStatus;
}
