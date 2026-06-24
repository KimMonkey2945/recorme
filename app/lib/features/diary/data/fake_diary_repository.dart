import '../../../core/error/failure.dart';
import '../../../shared/models/cursor_page.dart';
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

    for (final offset in dayOffsets.reversed.toList().reversed) {
      // 위 표현은 그대로 dayOffsets 순서를 유지(가독성용). 큰 값부터 들어 있다.
      final date = base.subtract(Duration(days: offset));
      final id = _nextId++;
      _diaries[id] = Diary(
        id: id,
        content: _sampleContents[id % _sampleContents.length],
        writtenDate: date,
        visibility: 'PRIVATE',
        analysisStatus: 'DONE',
        shareToken: 'seed-token-$id',
      );
    }
  }

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

  // ── DiaryRepository 구현 ────────────────────────────────────

  @override
  Future<DiarySummary> getMonthlySummary(String yearMonth) async {
    await Future<void>.delayed(_latency);
    final dates = _diaries.values
        .where((d) => _dateKey(d.writtenDate).startsWith(yearMonth))
        .map((d) => _dateKey(d.writtenDate))
        .toList()
      ..sort();
    return DiarySummary(yearMonth: yearMonth, dates: dates);
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
      items: page,
      nextCursor: nextCursor,
      hasNext: hasNext,
    );
  }

  @override
  Future<Diary> upsert({
    required DateTime date,
    required String content,
  }) async {
    await Future<void>.delayed(_latency);
    final key = _dateKey(date);

    // 같은 날짜의 활성 일기가 있으면 UPDATE(같은 id 유지).
    for (final entry in _diaries.entries) {
      if (_dateKey(entry.value.writtenDate) == key) {
        final updated = Diary(
          id: entry.key,
          content: content,
          writtenDate: entry.value.writtenDate,
          visibility: entry.value.visibility,
          analysisStatus: 'PENDING', // 내용 변경 → 재분석 대기(더미)
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
      writtenDate: DateTime(date.year, date.month, date.day),
      visibility: 'PRIVATE',
      analysisStatus: 'PENDING',
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
}
