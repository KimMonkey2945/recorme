// 피드 도메인 모델(손 작성 불변 클래스 — 프로젝트 freezed 미사용 관례).
// 백엔드 GET /feed(카드) · GET /feed/{id}(전문) 응답과 1:1 대응한다.

/// 공감 추가/취소 결과(POST/DELETE /diaries/{id}/reactions). UI 즉시 동기화용.
class ReactionResult {
  const ReactionResult({required this.reactionCount, required this.reacted});

  final int reactionCount;
  final bool reacted;

  factory ReactionResult.fromJson(Map<String, dynamic> json) => ReactionResult(
        reactionCount: (json['reactionCount'] as num?)?.toInt() ?? 0,
        reacted: json['reacted'] as bool? ?? false,
      );
}

/// 피드 카드 항목(GET /feed). 전문은 없고 감정 카드 요약만 담는다.
/// reactionCount/reactedByMe 는 Task 015-4(공감)에서 실제 값으로 채워진다(그 전엔 0/false).
class FeedItem {
  const FeedItem({
    required this.id,
    required this.authorUuid,
    required this.authorNickname,
    this.authorProfileImageUrl,
    this.moodEmoji,
    this.aiTitle,
    this.preview,
    required this.writtenDate,
    required this.visibility,
    this.primaryEmotion,
    this.backgroundColor,
    this.accentColor,
    this.reactionCount = 0,
    this.reactedByMe = false,
  });

  final int id;
  final String authorUuid;
  final String authorNickname;
  final String? authorProfileImageUrl;
  final String? moodEmoji;
  final String? aiTitle;
  final String? preview;
  final DateTime writtenDate;
  final String visibility;
  final String? primaryEmotion;
  final String? backgroundColor;
  final String? accentColor;
  final int reactionCount;
  final bool reactedByMe;

  /// 공감 상태만 바꾼 복제본(낙관적 갱신용).
  FeedItem copyWith({int? reactionCount, bool? reactedByMe}) => FeedItem(
        id: id,
        authorUuid: authorUuid,
        authorNickname: authorNickname,
        authorProfileImageUrl: authorProfileImageUrl,
        moodEmoji: moodEmoji,
        aiTitle: aiTitle,
        preview: preview,
        writtenDate: writtenDate,
        visibility: visibility,
        primaryEmotion: primaryEmotion,
        backgroundColor: backgroundColor,
        accentColor: accentColor,
        reactionCount: reactionCount ?? this.reactionCount,
        reactedByMe: reactedByMe ?? this.reactedByMe,
      );

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        id: (json['id'] as num).toInt(),
        authorUuid: json['authorUuid'] as String,
        authorNickname: json['authorNickname'] as String,
        authorProfileImageUrl: json['authorProfileImageUrl'] as String?,
        moodEmoji: json['moodEmoji'] as String?,
        aiTitle: json['aiTitle'] as String?,
        preview: json['preview'] as String?,
        writtenDate: DateTime.parse(json['writtenDate'] as String),
        visibility: json['visibility'] as String? ?? 'PUBLIC',
        primaryEmotion: json['primaryEmotion'] as String?,
        backgroundColor: json['backgroundColor'] as String?,
        accentColor: json['accentColor'] as String?,
        reactionCount: (json['reactionCount'] as num?)?.toInt() ?? 0,
        reactedByMe: json['reactedByMe'] as bool? ?? false,
      );
}

/// 피드 카드 탭 시 전문(GET /feed/{id}). 작성자 표시 정보 + 본문(Delta) + 감정 테마.
class FeedDetail {
  const FeedDetail({
    required this.id,
    required this.authorUuid,
    required this.authorNickname,
    this.authorProfileImageUrl,
    required this.content,
    this.contentText,
    required this.writtenDate,
    required this.visibility,
    this.primaryEmotion,
    this.backgroundColor,
    this.textColor,
    this.accentColor,
    this.aiComment,
    this.aiTitle,
    this.moodEmoji,
    this.reactionCount = 0,
    this.reactedByMe = false,
  });

  final int id;
  final String authorUuid;
  final String authorNickname;
  final String? authorProfileImageUrl;

  /// 본문 Quill Delta JSON 문자열(인라인 이미지 포함).
  final String content;
  final String? contentText;
  final DateTime writtenDate;
  final String visibility;
  final String? primaryEmotion;
  final String? backgroundColor;
  final String? textColor;
  final String? accentColor;
  final String? aiComment;
  final String? aiTitle;
  final String? moodEmoji;
  final int reactionCount;
  final bool reactedByMe;

  factory FeedDetail.fromJson(Map<String, dynamic> json) => FeedDetail(
        id: (json['id'] as num).toInt(),
        authorUuid: json['authorUuid'] as String,
        authorNickname: json['authorNickname'] as String,
        authorProfileImageUrl: json['authorProfileImageUrl'] as String?,
        content: json['content'] as String,
        contentText: json['contentText'] as String?,
        writtenDate: DateTime.parse(json['writtenDate'] as String),
        visibility: json['visibility'] as String? ?? 'PUBLIC',
        primaryEmotion: json['primaryEmotion'] as String?,
        backgroundColor: json['backgroundColor'] as String?,
        textColor: json['textColor'] as String?,
        accentColor: json['accentColor'] as String?,
        aiComment: json['aiComment'] as String?,
        aiTitle: json['aiTitle'] as String?,
        moodEmoji: json['moodEmoji'] as String?,
        reactionCount: (json['reactionCount'] as num?)?.toInt() ?? 0,
        reactedByMe: json['reactedByMe'] as bool? ?? false,
      );
}
