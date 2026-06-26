/// 일기 단건(상세/목록 공용). 감정/테마/음악(emotion·theme·track)은 Phase 4에서 확장.
/// (손 작성 불변 클래스 — shared/models/user.dart의 비고 참조)
///
/// 이미지는 본문(content)의 Quill Delta에 인라인 임베드로 포함된다(별도 첨부 테이블 없음).
/// 목록 표시용 대표 썸네일·개수는 백엔드가 content에서 산출해 [thumbnailUrl]·[imageCount]로 내려준다.
class Diary {
  const Diary({
    required this.id,
    required this.content,
    required this.writtenDate,
    required this.visibility,
    required this.analysisStatus,
    this.contentText,
    this.shareToken,
    this.thumbnailUrl,
    this.imageCount = 0,
  });

  final int id;

  /// 본문. 상세 응답에서는 **Quill Delta JSON 문자열**, 목록 응답에서는 서식을
  /// 제거한 순수 텍스트 미리보기다(백엔드가 content_text 값을 content 키로 내려줌).
  final String content;

  /// 서식·이미지를 제거한 순수 텍스트(글자수·검색·LLM 입력용). 상세 응답에만 존재.
  final String? contentText;

  final DateTime writtenDate;
  final String visibility;
  final String analysisStatus;
  final String? shareToken;

  /// 목록 응답의 대표 이미지 상대 경로(없으면 null). 상세 응답엔 보통 없다.
  final String? thumbnailUrl;

  /// 본문에 포함된 이미지 개수(목록 배지용).
  final int imageCount;

  factory Diary.fromJson(Map<String, dynamic> json) {
    return Diary(
      id: (json['id'] as num).toInt(),
      content: json['content'] as String,
      contentText: json['contentText'] as String?,
      writtenDate: DateTime.parse(json['writtenDate'] as String),
      // 목록 응답(DiaryListItem)에는 visibility/shareToken이 없다.
      // 상세 응답(DiaryResponse)에는 그대로 들어오므로 tolerant하게 기본값 처리.
      visibility: json['visibility'] as String? ?? 'PRIVATE',
      analysisStatus: json['analysisStatus'] as String,
      shareToken: json['shareToken'] as String?,
      // 목록 응답의 대표 썸네일 경로(상세 응답엔 없을 수 있음).
      thumbnailUrl: json['thumbnailUrl'] as String?,
      imageCount: (json['imageCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'contentText': contentText,
        'writtenDate': writtenDate.toIso8601String(),
        'visibility': visibility,
        'analysisStatus': analysisStatus,
        'shareToken': shareToken,
        'thumbnailUrl': thumbnailUrl,
        'imageCount': imageCount,
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
