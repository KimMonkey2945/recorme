import '../../../core/error/failure.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/resolution.dart';
import '../domain/resolution_repository.dart';

/// 인메모리 더미 결심 저장소(테스트/개발용).
///
/// 실제 백엔드 없이 목록·캘린더·단건 조회·생성·완료 체크·연장·취소를 시뮬레이션한다.
/// 모든 메서드는 네트워크 지연을 흉내 내기 위해 약간의 delay를 둔다.
/// 실제 환경에서는 이 클래스만 [ApiResolutionRepository]로 교체하면 화면 코드는 그대로 동작한다.
/// (FakeDiaryRepository 스타일을 미러링한다.)
class FakeResolutionRepository implements ResolutionRepository {
  FakeResolutionRepository() {
    _seed();
  }

  /// 활성 결심 저장소(id → Resolution). 소프트 삭제 시 여기서 제거한다.
  final Map<int, Resolution> _resolutions = {};

  /// 다음에 발급할 id. 시드 이후 최댓값+1로 맞춘다.
  int _nextId = 1;

  /// 네트워크 지연 흉내.
  static const _latency = Duration(milliseconds: 300);

  // ── 시드 데이터 ──────────────────────────────────────────────

  /// 진행 중 1건 + 성공 1건 + 실패 1건을 만들어 탭·도트·캘린더를 테스트한다.
  /// 과거가 작은 id를 받아 id 내림차순 = 최신순이 되도록 순서대로 생성한다.
  void _seed() {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);

    // 실패(과거): 시작 5일 전, 1일차만 DONE 후 놓침 → FAILED.
    _insertSeed(
      startDate: base.subtract(const Duration(days: 5)),
      title: '아침 6시 기상',
      status: ResolutionStatus.failed,
      dayStatuses: const [CheckStatus.done, CheckStatus.missed, CheckStatus.missed],
      reminderTime: '06:00',
    );

    // 성공(과거): 시작 4일 전, 3일 모두 DONE → SUCCESS(연장 가능).
    _insertSeed(
      startDate: base.subtract(const Duration(days: 4)),
      title: '물 2L 마시기',
      status: ResolutionStatus.success,
      dayStatuses: const [CheckStatus.done, CheckStatus.done, CheckStatus.done],
      reminderTime: null,
    );

    // 진행 중(오늘 시작): 1일차 오늘 PENDING.
    _insertSeed(
      startDate: base,
      title: '30분 러닝',
      status: ResolutionStatus.ongoing,
      dayStatuses: const [CheckStatus.pending, CheckStatus.pending, CheckStatus.pending],
      reminderTime: '20:30',
    );
  }

  /// 시드 1건 삽입. [dayStatuses]로 1·2·3일차 체크를 구성한다.
  void _insertSeed({
    required DateTime startDate,
    required String title,
    required ResolutionStatus status,
    required List<CheckStatus> dayStatuses,
    String? reminderTime,
  }) {
    final id = _nextId++;
    final checks = [
      for (var i = 0; i < dayStatuses.length; i++)
        ResolutionCheck(
          checkDate: startDate.add(Duration(days: i)),
          dayIndex: i + 1,
          status: dayStatuses[i],
          completedAt: dayStatuses[i] == CheckStatus.done
              ? startDate.add(Duration(days: i, hours: 21))
              : null,
        ),
    ];
    _resolutions[id] = Resolution(
      id: id,
      title: title,
      startDate: startDate,
      endDate: startDate.add(const Duration(days: 2)),
      status: status,
      streakSeq: 1,
      reminderTime: reminderTime,
      checks: checks,
    );
  }

  // ── 유틸 ────────────────────────────────────────────────────

  /// 시간 정보를 버린 날짜 키('yyyy-MM-dd').
  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Resolution → 목록 항목(경량). 체크 상태를 dayStatuses 리스트로 축약한다.
  ResolutionSummaryItem _asSummary(Resolution r) => ResolutionSummaryItem(
        id: r.id,
        title: r.title,
        startDate: r.startDate,
        endDate: r.endDate,
        status: r.status,
        streakSeq: r.streakSeq,
        dayStatuses: r.checks.map((c) => c.status).toList(),
      );

  // ── ResolutionRepository 구현 ───────────────────────────────

  @override
  Future<Resolution> create({
    required String title,
    required DateTime startDate,
    String? reminderTime,
  }) async {
    await Future<void>.delayed(_latency);
    final id = _nextId++;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    // 생성 시 3일치 체크를 PENDING으로 프리생성(서버 generate_series 동작 미러링).
    final checks = [
      for (var i = 0; i < 3; i++)
        ResolutionCheck(
          checkDate: start.add(Duration(days: i)),
          dayIndex: i + 1,
          status: CheckStatus.pending,
        ),
    ];
    final created = Resolution(
      id: id,
      title: title,
      startDate: start,
      endDate: start.add(const Duration(days: 2)),
      status: ResolutionStatus.ongoing,
      streakSeq: 1,
      reminderTime: reminderTime,
      checks: checks,
    );
    _resolutions[id] = created;
    return created;
  }

  @override
  Future<CursorPage<ResolutionSummaryItem>> getList(
    ResolutionStatus? status, {
    int? cursor,
    int size = 20,
  }) async {
    await Future<void>.delayed(_latency);
    // id 내림차순 정렬 후, status 필터 → cursor 미만만 취한다(OFFSET 미사용).
    final sorted = _resolutions.values.toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    final byStatus = status == null
        ? sorted
        : sorted.where((r) => r.status == status).toList();
    final filtered = cursor == null
        ? byStatus
        : byStatus.where((r) => r.id < cursor).toList();
    final page = filtered.take(size).toList();
    final hasNext = filtered.length > size;
    final nextCursor = (hasNext && page.isNotEmpty) ? page.last.id : null;
    return CursorPage<ResolutionSummaryItem>(
      items: page.map(_asSummary).toList(),
      nextCursor: nextCursor,
      hasNext: hasNext,
    );
  }

  @override
  Future<List<ResolutionCalendarDay>> getCalendar(String yearMonth) async {
    await Future<void>.delayed(_latency);
    // 활성 결심의 모든 체크를 (날짜, 결심)당 1행으로 펼쳐 해당 월만 반환한다.
    final days = <ResolutionCalendarDay>[];
    for (final r in _resolutions.values) {
      for (final c in r.checks) {
        if (_dateKey(c.checkDate).startsWith(yearMonth)) {
          days.add(ResolutionCalendarDay(
            date: c.checkDate,
            resolutionId: r.id,
            title: r.title,
            resolutionStatus: r.status,
            checkStatus: c.status,
          ));
        }
      }
    }
    days.sort((a, b) {
      final byDate = _dateKey(a.date).compareTo(_dateKey(b.date));
      return byDate != 0 ? byDate : a.resolutionId.compareTo(b.resolutionId);
    });
    return days;
  }

  @override
  Future<Resolution> getById(int id) async {
    await Future<void>.delayed(_latency);
    final r = _resolutions[id];
    if (r == null) {
      throw const Failure('RESOLUTION_NOT_FOUND', '결심을 찾을 수 없습니다.');
    }
    return r;
  }

  @override
  Future<Resolution> completeToday(int id) async {
    await Future<void>.delayed(_latency);
    final r = _resolutions[id];
    if (r == null) {
      throw const Failure('RESOLUTION_NOT_FOUND', '결심을 찾을 수 없습니다.');
    }
    if (r.status != ResolutionStatus.ongoing) {
      throw const Failure('RESOLUTION_NOT_ACTIVE', '진행 중인 결심이 아니에요.');
    }
    final todayKey = _dateKey(DateTime.now());
    final idx = r.checks.indexWhere((c) => _dateKey(c.checkDate) == todayKey);
    if (idx < 0) {
      throw const Failure('CHECK_NOT_TODAY', '오늘 완료할 체크가 없어요.');
    }
    // PENDING → DONE 전이(멱등: 이미 DONE이면 그대로 둔다).
    final updatedChecks = [...r.checks];
    final target = updatedChecks[idx];
    if (target.status == CheckStatus.pending) {
      updatedChecks[idx] = ResolutionCheck(
        checkDate: target.checkDate,
        dayIndex: target.dayIndex,
        status: CheckStatus.done,
        completedAt: DateTime.now(),
      );
    }
    // 3일 모두 DONE이면 결심 SUCCESS 전이.
    final allDone = updatedChecks.every((c) => c.status == CheckStatus.done);
    final updated = Resolution(
      id: r.id,
      title: r.title,
      startDate: r.startDate,
      endDate: r.endDate,
      status: allDone ? ResolutionStatus.success : r.status,
      streakSeq: r.streakSeq,
      reminderTime: r.reminderTime,
      checks: updatedChecks,
    );
    _resolutions[id] = updated;
    return updated;
  }

  @override
  Future<Resolution> extend(int id, {String? reminderTime}) async {
    await Future<void>.delayed(_latency);
    final prev = _resolutions[id];
    if (prev == null) {
      throw const Failure('RESOLUTION_NOT_FOUND', '결심을 찾을 수 없습니다.');
    }
    if (prev.status != ResolutionStatus.success) {
      throw const Failure('NOT_EXTENDABLE', '성공한 결심만 연장할 수 있어요.');
    }
    // 다음 3일을 새 결심(같은 체인, streakSeq+1)으로 이어 붙인다.
    final newId = _nextId++;
    final newStart = prev.endDate.add(const Duration(days: 1));
    final checks = [
      for (var i = 0; i < 3; i++)
        ResolutionCheck(
          checkDate: newStart.add(Duration(days: i)),
          dayIndex: i + 1,
          status: CheckStatus.pending,
        ),
    ];
    final created = Resolution(
      id: newId,
      title: prev.title,
      startDate: newStart,
      endDate: newStart.add(const Duration(days: 2)),
      status: ResolutionStatus.ongoing,
      streakSeq: prev.streakSeq + 1,
      // 미지정이면 이전 결심의 알림 시각 승계.
      reminderTime: reminderTime ?? prev.reminderTime,
      checks: checks,
    );
    _resolutions[newId] = created;
    return created;
  }

  @override
  Future<Resolution> update(
    int id, {
    required String title,
    String? reminderTime,
  }) async {
    await Future<void>.delayed(_latency);
    final r = _resolutions[id];
    if (r == null) {
      throw const Failure('RESOLUTION_NOT_FOUND', '결심을 찾을 수 없습니다.');
    }
    if (r.status != ResolutionStatus.ongoing) {
      throw const Failure('RESOLUTION_NOT_ACTIVE', '진행 중인 결심이 아니에요.');
    }
    // 제목·알림 시각만 갱신한다(시작일·체크는 그대로 유지).
    final updated = Resolution(
      id: r.id,
      title: title,
      startDate: r.startDate,
      endDate: r.endDate,
      status: r.status,
      streakSeq: r.streakSeq,
      reminderTime: reminderTime,
      checks: r.checks,
    );
    _resolutions[id] = updated;
    return updated;
  }

  @override
  Future<void> cancel(int id) async {
    await Future<void>.delayed(_latency);
    // 소프트 삭제 시뮬레이션: 활성 저장소에서 제거한다.
    _resolutions.remove(id);
  }
}
