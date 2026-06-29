import 'dart:typed_data';

import '../../../core/error/failure.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/diary_content.dart';
import '../domain/diary_repository.dart';
import 'dto/diary_dto.dart';

/// 인메모리 더미 일기 저장소(Phase 2 전용).
///
/// 실제 백엔드 없이 캘린더 dot·목록 커서 페이징·단건 조회·upsert·소프트 삭제를
/// 시뮬레이션한다. 모든 메서드는 네트워크 지연을 흉내 내기 위해 약간의 delay를 둔다.
/// Phase 3에서 이 클래스만 `ApiDiaryRepository`로 교체하면 화면 코드는 그대로 동작한다.
class FakeDiaryRepository implements DiaryRepository {
  FakeDiaryRepository() {
    _seed();
  }

  /// 활성 일기 저장소(id → Diary). 소프트 삭제 시 여기서 제거한다.
  final Map<int, Diary> _diaries = {};

  /// 다음에 발급할 id. 시드 이후 최댓값+1로 맞춘다.
  int _nextId = 1;

  /// 네트워크 지연 흉내.
  static const _latency = Duration(milliseconds: 300);

  // ── 시드 데이터 ──────────────────────────────────────────────

  /// 최근 약 6주 범위에 듬성듬성 더미 일기를 생성한다.
  /// 오래된 날짜일수록 작은 id를 받아, id 내림차순 = 날짜 내림차순이 되도록 한다.
  void _seed() {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);

    // 오늘로부터의 일수 차이(작성된 날). 비어 있는 날을 섞어 캘린더에 빈칸이 보이게 한다.
    // 큰 값(과거)부터 순회해야 과거가 작은 id를 받는다.
    const dayOffsets = [38, 35, 31, 28, 24, 21, 19, 16, 14, 11, 9, 7, 5, 3, 1, 0];

    // dayOffsets는 이미 큰 값(과거)부터 정렬돼 있어, 순서대로 순회하면 과거가 작은 id를 받는다.
    for (final offset in dayOffsets) {
      final date = base.subtract(Duration(days: offset));
      final id = _nextId++;
      final text = _sampleContents[id % _sampleContents.length];
      // 감정 테마 더미 데이터 — id별로 다른 감정을 순환해 상세 화면 배경 전환을 테스트한다.
      final theme = _sampleThemes[id % _sampleThemes.length];
      _diaries[id] = Diary(
        id: id,
        // 신버전 본문은 Delta JSON 문자열로 저장된다(시드도 동일하게 래핑).
        content: contentJsonFromPlain(text),
        contentText: text,
        writtenDate: date,
        visibility: 'PRIVATE',
        analysisStatus: 'DONE',
        shareToken: 'seed-token-$id',
        primaryEmotion: theme.primaryEmotion,
        backgroundColor: theme.backgroundColor,
        textColor: theme.textColor,
        accentColor: theme.accentColor,
        moodEmoji: theme.moodEmoji,
        aiComment: theme.aiComment,
        aiTitle: theme.aiTitle,
      );
    }
  }

  /// 감정별 더미 테마 데이터 레코드.
  ///
  /// primaryEmotion은 [DiaryTheme]의 팔레트 키와 일치해야 배경색이 올바르게 적용된다.
  /// backgroundColor/textColor/accentColor는 DTO 필드 완전성을 위해 유지하되,
  /// 렌더는 [DiaryTheme.fromEmotion]이 팔레트를 결정론적으로 덮어쓴다.
  static const List<_EmotionTheme> _sampleThemes = [
    _EmotionTheme(
      primaryEmotion: 'JOY',       // DiaryTheme.joy → #FFF3D6(연노랑)
      backgroundColor: '#FFF3D6',
      textColor: '#3A2E12',
      accentColor: '#F5A623',
      moodEmoji: '😊',
      aiComment: '햇살처럼 따뜻했던 하루',
      aiTitle: '빛나는 오후의 산책',
    ),
    _EmotionTheme(
      primaryEmotion: 'CALM',      // DiaryTheme.calm → #E2F1E8(연초록)
      backgroundColor: '#E2F1E8',
      textColor: '#1C2B22',
      accentColor: '#4CA06A',
      moodEmoji: '😌',
      aiComment: '잔잔하게 흘러간 날',
      aiTitle: '고요한 일상의 리듬',
    ),
    _EmotionTheme(
      primaryEmotion: 'SADNESS',   // DiaryTheme.sadness → #E3EDF7(연파랑)
      backgroundColor: '#E3EDF7',
      textColor: '#1F2A37',
      accentColor: '#4A77B5',
      moodEmoji: '😔',
      aiComment: '마음 한켠이 조금 무거웠어요',
      aiTitle: '비 오는 날 창가에서',
    ),
    _EmotionTheme(
      primaryEmotion: 'ANGER',     // DiaryTheme.anger → #FBE3DE(연코랄)
      backgroundColor: '#FBE3DE',
      textColor: '#3A1A14',
      accentColor: '#D64531',
      moodEmoji: '😤',
      aiComment: '속에서 뭔가 끓어오른 하루',
      aiTitle: '참았지만 역시 힘들었던',
    ),
    _EmotionTheme(
      primaryEmotion: 'ANXIETY',   // DiaryTheme.anxiety → #ECE6F6(연보라)
      backgroundColor: '#ECE6F6',
      textColor: '#25203A',
      accentColor: '#7A5AC2',
      moodEmoji: '😟',
      aiComment: '마음이 조금 뒤숭숭했어요',
      aiTitle: '불안했지만 버텨낸 하루',
    ),
  ];

  /// 더미 일기 본문 샘플(길이 다양 — 목록 2줄 말줄임 확인용).
  static const List<String> _sampleContents = [
    '오늘은 날씨가 좋았다. 오후에 가볍게 산책을 했고 마음이 한결 편해졌다. 저녁에는 오랜만에 친구들과 만나 즐거운 시간을 보냈다.',
    '바쁜 하루였다. 할 일이 많아 정신없이 지나갔지만, 하나씩 끝내고 나니 뿌듯한 기분이 들었다.',
    '비가 내렸다. 창밖을 보며 따뜻한 차를 마셨다. 조용한 하루가 오히려 위로가 되었다.',
    '운동을 다시 시작했다. 몸은 힘들었지만 개운한 느낌. 꾸준히 해보자고 다짐했다.',
    '책을 한 권 다 읽었다. 마지막 장을 덮으며 여운이 오래 남았다.',
    '조금 우울한 날이었다. 별일 없었는데도 기운이 나지 않았다. 일찍 자기로 했다.',
    '새로운 카페를 발견했다. 분위기도 좋고 커피도 맛있어서 자주 오고 싶어졌다.',
    '가족과 통화했다. 별 내용 아니었지만 목소리를 들으니 안심이 됐다.',
  ];

  // ── 유틸 ────────────────────────────────────────────────────

  /// 시간 정보를 버린 날짜 키('yyyy-MM-dd').
  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 목록 아이템 표현으로 변환한다(백엔드 미러링).
  ///
  /// 목록 응답의 `content`는 서식을 제거한 **순수 텍스트 미리보기**다(상세는 Delta JSON).
  Diary _asListItem(Diary d) => Diary(
        id: d.id,
        content: d.contentText ?? plainTextOf(documentFromContent(d.content)),
        writtenDate: d.writtenDate,
        visibility: d.visibility,
        analysisStatus: d.analysisStatus,
        thumbnailUrl: d.thumbnailUrl,
        imageCount: d.imageCount,
      );

  // ── DiaryRepository 구현 ────────────────────────────────────

  @override
  Future<DiarySummary> getMonthlySummary(String yearMonth) async {
    await Future<void>.delayed(_latency);
    // 해당 월 일기를 날짜 오름차순으로 정렬해 DiarySummaryDay 목록으로 변환한다.
    final days = (_diaries.values
          .where((d) => _dateKey(d.writtenDate).startsWith(yearMonth))
          .toList()
        ..sort((a, b) =>
            _dateKey(a.writtenDate).compareTo(_dateKey(b.writtenDate))))
        .map((d) => DiarySummaryDay(
              date: _dateKey(d.writtenDate),
              analysisStatus: d.analysisStatus,
              primaryEmotion: d.primaryEmotion,
              moodEmoji: d.moodEmoji,
            ))
        .toList();
    return DiarySummary(yearMonth: yearMonth, days: days);
  }

  @override
  Future<Diary?> getByDate(DateTime date) async {
    await Future<void>.delayed(_latency);
    final key = _dateKey(date);
    for (final diary in _diaries.values) {
      if (_dateKey(diary.writtenDate) == key) return diary;
    }
    return null;
  }

  @override
  Future<Diary> getById(int id) async {
    await Future<void>.delayed(_latency);
    final diary = _diaries[id];
    if (diary == null) {
      throw const Failure('DIARY_NOT_FOUND', '일기를 찾을 수 없습니다.');
    }
    return diary;
  }

  @override
  Future<CursorPage<Diary>> getList({int? cursor, int size = 20}) async {
    await Future<void>.delayed(_latency);
    // id 내림차순 정렬 후, cursor(마지막으로 본 id) 미만만 취한다(OFFSET 미사용).
    final sorted = _diaries.values.toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    final filtered =
        cursor == null ? sorted : sorted.where((d) => d.id < cursor).toList();
    final page = filtered.take(size).toList();
    final hasNext = filtered.length > size;
    final nextCursor = (hasNext && page.isNotEmpty) ? page.last.id : null;
    return CursorPage<Diary>(
      items: page.map(_asListItem).toList(),
      nextCursor: nextCursor,
      hasNext: hasNext,
    );
  }

  @override
  Future<List<Diary>> getMonthList(String yearMonth) async {
    await Future<void>.delayed(_latency);
    final items = _diaries.values
        .where((d) => _dateKey(d.writtenDate).startsWith(yearMonth))
        .toList()
      ..sort((a, b) => b.writtenDate.compareTo(a.writtenDate));
    return items.map(_asListItem).toList();
  }

  @override
  Future<Diary> upsert({
    required DateTime date,
    required String content,
    required String contentText,
    bool confirm = false,
  }) async {
    await Future<void>.delayed(_latency);
    final key = _dateKey(date);

    // 같은 날짜의 활성 일기가 있으면 UPDATE(같은 id 유지).
    for (final entry in _diaries.entries) {
      if (_dateKey(entry.value.writtenDate) == key) {
        // 이미 확정된 일기를 수정 시도하면 409 시뮬레이션.
        if (!entry.value.isDraft) {
          throw const Failure(
            'DIARY_ALREADY_CONFIRMED',
            '이미 기억한 일기는 수정할 수 없어요.',
          );
        }
        final updated = Diary(
          id: entry.key,
          content: content,
          contentText: contentText,
          writtenDate: entry.value.writtenDate,
          visibility: entry.value.visibility,
          // confirm=true → 확정(PENDING, 분석 요청), false → 임시 저장(DRAFT)
          analysisStatus: confirm ? 'PENDING' : 'DRAFT',
          shareToken: entry.value.shareToken,
        );
        _diaries[entry.key] = updated;
        return updated;
      }
    }

    // 없으면 INSERT(새 id).
    final id = _nextId++;
    final created = Diary(
      id: id,
      content: content,
      contentText: contentText,
      writtenDate: DateTime(date.year, date.month, date.day),
      visibility: 'PRIVATE',
      // confirm=true → PENDING, false → DRAFT
      analysisStatus: confirm ? 'PENDING' : 'DRAFT',
      shareToken: 'token-$id',
    );
    _diaries[id] = created;
    return created;
  }

  @override
  Future<void> delete(int id) async {
    await Future<void>.delayed(_latency);
    // 소프트 삭제 시뮬레이션: 활성 저장소에서 제거하면 해당 날짜 재작성이 가능해진다.
    _diaries.remove(id);
  }

  @override
  Future<String> uploadImage(Uint8List bytes, String filename) async {
    // 인메모리 더미: 실제 저장 없이 가짜 상대 경로를 돌려준다.
    await Future<void>.delayed(_latency);
    return '/files/diaries/fake/${_nextId++}_$filename';
  }
}

// ── 헬퍼 ────────────────────────────────────────────────────────

/// 더미 감정 테마 값 묶음(시드 데이터 전용 레코드).
final class _EmotionTheme {
  const _EmotionTheme({
    required this.primaryEmotion,
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
    required this.moodEmoji,
    required this.aiComment,
    required this.aiTitle,
  });

  final String primaryEmotion;
  final String backgroundColor;
  final String textColor;
  final String accentColor;
  final String moodEmoji;
  final String aiComment;
  final String aiTitle;
}
