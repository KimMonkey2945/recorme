/// 기록 단건(상세/목록 공용).
/// (손 작성 불변 클래스 — shared/models/user.dart의 비고 참조)
///
/// 이미지는 본문(content)의 Quill Delta에 인라인 임베드로 포함된다(별도 첨부 테이블 없음).
/// 목록 표시용 대표 썸네일·개수는 백엔드가 content에서 산출해 [thumbnailUrl]·[imageCount]로 내려준다.
///
/// ## 감정 테마 필드 (analysisStatus == 'DONE'일 때만 채워짐, 그 외 null)
/// - [backgroundColor]: 배경 hex (예: "#F7F5F0")
/// - [textColor]: 본문 잉크 hex (예: "#333333")
/// - [accentColor]: 강조색 hex (예: "#FF9800")
/// - [primaryEmotion]: 감정 코드 (예: "JOY")
/// - [moodEmoji]: 무드 이모지 (예: "😊")
/// - [aiComment]: AI 한 줄 코멘트
/// - [aiTitle]: AI 생성 제목
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
    // 감정 테마 필드 (DONE 시에만 채워짐)
    this.primaryEmotion,
    this.backgroundColor,
    this.textColor,
    this.accentColor,
    this.moodEmoji,
    this.aiComment,
    this.aiTitle,
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

  // ── 감정 테마 (DONE 시에만 비-null) ────────────────────────────

  /// 분류된 감정 코드 (예: "JOY", "SADNESS").
  final String? primaryEmotion;

  /// 배경 색상 hex 문자열 (예: "#F7F5F0"). [Color]로 변환하려면 [backgroundColorHex] 사용.
  final String? backgroundColor;

  /// 본문 잉크 색상 hex 문자열 (예: "#333333").
  final String? textColor;

  /// UI 강조 색상 hex 문자열 (예: "#FF9800").
  final String? accentColor;

  /// 무드 이모지 문자열 (예: "😊").
  final String? moodEmoji;

  /// AI가 생성한 한 줄 감정 코멘트.
  final String? aiComment;

  /// AI가 생성한 기록 제목.
  final String? aiTitle;

  // ── 편의 getter ──────────────────────────────────────────────

  /// 임시 저장 여부. DRAFT 상태면 true(수정 가능), 아니면 확정 상태(수정 불가).
  bool get isDraft => analysisStatus == 'DRAFT';

  /// 감정 테마가 완전히 채워진 상태인지 여부.
  bool get hasTheme => analysisStatus == 'DONE' && backgroundColor != null;

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
      // 감정 테마 필드 — DONE이 아니면 서버가 null을 내려줌. tolerant 파싱.
      primaryEmotion: json['primaryEmotion'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      accentColor: json['accentColor'] as String?,
      moodEmoji: json['moodEmoji'] as String?,
      aiComment: json['aiComment'] as String?,
      aiTitle: json['aiTitle'] as String?,
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
        'primaryEmotion': primaryEmotion,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'accentColor': accentColor,
        'moodEmoji': moodEmoji,
        'aiComment': aiComment,
        'aiTitle': aiTitle,
      };

  /// 일부 필드만 바꾼 복제본. 공개범위 변경 등 부분 갱신에 사용한다.
  Diary copyWith({String? visibility}) => Diary(
        id: id,
        content: content,
        contentText: contentText,
        writtenDate: writtenDate,
        visibility: visibility ?? this.visibility,
        analysisStatus: analysisStatus,
        shareToken: shareToken,
        thumbnailUrl: thumbnailUrl,
        imageCount: imageCount,
        primaryEmotion: primaryEmotion,
        backgroundColor: backgroundColor,
        textColor: textColor,
        accentColor: accentColor,
        moodEmoji: moodEmoji,
        aiComment: aiComment,
        aiTitle: aiTitle,
      );
}

/// GET /diaries/me/summary 응답의 날짜별 감정 요약 항목.
///
/// 백엔드 `days` 배열의 각 원소에 대응한다.
/// [analysisStatus]가 'DONE'일 때만 [primaryEmotion]·[moodEmoji]가 채워진다.
class DiarySummaryDay {
  const DiarySummaryDay({
    required this.date,
    required this.analysisStatus,
    this.primaryEmotion,
    this.moodEmoji,
  });

  /// 날짜 문자열 ('yyyy-MM-dd').
  final String date;

  /// 분석 상태 코드 ('DRAFT', 'PENDING', 'DONE').
  final String analysisStatus;

  /// 감정 코드 (DONE 시에만 비-null). 예: 'JOY', 'SADNESS'.
  final String? primaryEmotion;

  /// 무드 이모지 (DONE 시에만 비-null). 예: '😊'.
  final String? moodEmoji;

  /// 감정 분석 완료 여부.
  bool get isDone => analysisStatus == 'DONE';

  /// 임시 저장 상태 여부.
  bool get isDraft => analysisStatus == 'DRAFT';

  factory DiarySummaryDay.fromJson(Map<String, dynamic> json) =>
      DiarySummaryDay(
        date: json['date'] as String,
        // tolerant 파싱 — 필드 누락 시 DRAFT로 폴백한다.
        analysisStatus: json['analysisStatus'] as String? ?? 'DRAFT',
        primaryEmotion: json['primaryEmotion'] as String?,
        moodEmoji: json['moodEmoji'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'analysisStatus': analysisStatus,
        'primaryEmotion': primaryEmotion,
        'moodEmoji': moodEmoji,
      };
}

/// GET /diaries/me/summary 응답 — 캘린더 감정색·이모지 렌더링용.
///
/// 기존 `dates: [...]` 문자열 배열을 `days: [...]` 객체 배열로 대체한다.
/// 각 항목의 [DiarySummaryDay.analysisStatus]·[DiarySummaryDay.primaryEmotion]로
/// 날짜 셀에 감정 팔레트·이모지를 표시한다.
class DiarySummary {
  const DiarySummary({required this.yearMonth, required this.days});

  final String yearMonth;
  final List<DiarySummaryDay> days;

  factory DiarySummary.fromJson(Map<String, dynamic> json) => DiarySummary(
        yearMonth: json['yearMonth'] as String,
        days: (json['days'] as List<dynamic>)
            .map((e) => DiarySummaryDay.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'yearMonth': yearMonth,
        'days': days.map((d) => d.toJson()).toList(),
      };
}
