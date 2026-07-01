import '../../../shared/models/cursor_page.dart';
import 'resolution.dart';

/// 작심삼일(결심) 데이터 접근 추상화.
///
/// [FakeResolutionRepository]가 인메모리 더미로 구현하고, 실제 환경에서는
/// 동일 인터페이스의 [ApiResolutionRepository](실제 API)로 교체한다.
/// 메서드 시그니처는 `ResolutionController`의 엔드포인트와 1:1로 대응한다.
/// (경로는 dio baseUrl에 `/api/v1`이 포함되므로 `/resolutions...`만 쓴다.)
abstract class ResolutionRepository {
  /// 결심 생성. 종료일은 서버가 `startDate + 2`로 파생한다.
  /// [reminderTime]은 'HH:mm[:ss]' 문자열(없으면 null → 알림 없음).
  /// POST /resolutions → 201 ResolutionDetail
  Future<Resolution> create({
    required String title,
    required DateTime startDate,
    String? reminderTime,
  });

  /// 내 결심 목록(커서 페이징, id 내림차순). [status]가 null이면 전체.
  /// [cursor]가 null이면 첫 페이지.
  /// GET /resolutions/me?status=&cursor=&size=
  Future<CursorPage<ResolutionSummaryItem>> getList(
    ResolutionStatus? status, {
    int? cursor,
    int size,
  });

  /// 월별 캘린더((날짜 × 결심)당 1행). [yearMonth]는 'yyyy-MM' 형식.
  /// GET /resolutions/me/calendar?yearMonth=
  Future<List<ResolutionCalendarDay>> getCalendar(String yearMonth);

  /// id 기반 단건 상세(헤더 + 3일 체크). 없으면 [Failure]('RESOLUTION_NOT_FOUND').
  /// GET /resolutions/{id}
  Future<Resolution> getById(int id);

  /// 오늘자 완료 체크(멱등). 갱신된 상세를 돌려준다.
  /// POST /resolutions/{id}/checks/today
  Future<Resolution> completeToday(int id);

  /// 성공한 결심을 '다음 3일'로 연장(같은 streak_group). 새 결심 상세를 돌려준다.
  /// [reminderTime]이 null이면 이전 결심의 알림 시각을 승계한다.
  /// POST /resolutions/{id}/extend → 201 ResolutionDetail
  Future<Resolution> extend(int id, {String? reminderTime});

  /// 결심 취소(소프트 삭제).
  /// DELETE /resolutions/{id}
  Future<void> cancel(int id);
}
