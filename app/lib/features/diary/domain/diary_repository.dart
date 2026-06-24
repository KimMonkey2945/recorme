import '../../../shared/models/cursor_page.dart';
import '../data/dto/diary_dto.dart';

/// 일기 데이터 접근 추상화.
///
/// Phase 2에서는 [FakeDiaryRepository]가 인메모리 더미로 구현하고,
/// Phase 3에서 동일 인터페이스의 `ApiDiaryRepository`(실제 API)로 교체한다.
/// 메서드 시그니처는 `docs/api-contract.md`의 엔드포인트와 1:1로 대응한다.
abstract class DiaryRepository {
  /// 월별 작성 요약(캘린더 dot용). [yearMonth]는 'yyyy-MM' 형식.
  /// GET /diaries/me/summary?yearMonth=
  Future<DiarySummary> getMonthlySummary(String yearMonth);

  /// 특정 날짜의 활성 일기. 없으면 null.
  /// GET /diaries/by-date/{date} (404 → null)
  Future<Diary?> getByDate(DateTime date);

  /// id 기반 단건 조회. 없으면 [Failure]('DIARY_NOT_FOUND').
  /// GET /diaries/{id}
  Future<Diary> getById(int id);

  /// 커서 페이징 목록(id 내림차순). [cursor]가 null이면 첫 페이지.
  /// GET /diaries/me?cursor=&size=
  Future<CursorPage<Diary>> getList({int? cursor, int size});

  /// 날짜+내용 upsert(하루 1기록). 같은 날짜가 있으면 UPDATE, 없으면 INSERT.
  /// POST /diaries
  Future<Diary> upsert({required DateTime date, required String content});

  /// 소프트 삭제. 삭제 후 같은 날짜 재작성이 허용된다.
  /// DELETE /diaries/{id}
  Future<void> delete(int id);
}
