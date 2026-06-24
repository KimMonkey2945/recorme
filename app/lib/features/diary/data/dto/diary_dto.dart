/// 일기 단건(상세/목록 공용). 감정/테마/음악(emotion·theme·track)은 Phase 4에서 확장.
/// (손 작성 불변 클래스 — shared/models/user.dart의 비고 참조)
class Diary {
  const Diary({
    required this.id,
    required this.content,
    required this.writtenDate,
    required this.visibility,
    required this.analysisStatus,
    this.shareToken,
  });

  final int id;
  final String content;
  final DateTime writtenDate;
  final String visibility;
  final String analysisStatus;
  final String? shareToken;

  factory Diary.fromJson(Map<String, dynamic> json) => Diary(
        id: (json['id'] as num).toInt(),
        content: json['content'] as String,
        writtenDate: DateTime.parse(json['writtenDate'] as String),
        visibility: json['visibility'] as String,
        analysisStatus: json['analysisStatus'] as String,
        shareToken: json['shareToken'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'writtenDate': writtenDate.toIso8601String(),
        'visibility': visibility,
        'analysisStatus': analysisStatus,
        'shareToken': shareToken,
      };
}

/// GET /diaries/me/summary 응답 — 캘린더 dot 렌더링용(해당 월 기록 존재 날짜 목록).
class DiarySummary {
  const DiarySummary({required this.yearMonth, required this.dates});

  final String yearMonth;
  final List<String> dates;

  factory DiarySummary.fromJson(Map<String, dynamic> json) => DiarySummary(
        yearMonth: json['yearMonth'] as String,
        dates: (json['dates'] as List<dynamic>).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'yearMonth': yearMonth,
        'dates': dates,
      };
}
