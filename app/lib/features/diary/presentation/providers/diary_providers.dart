import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/api_diary_repository.dart';
import '../../data/dto/diary_dto.dart';
import '../../domain/diary_repository.dart';

/// 기록 저장소 주입 지점.
///
/// 실제 API 구현([ApiDiaryRepository])을 주입한다.
/// 테스트에서는 `ProviderScope(overrides: [...])`로 `FakeDiaryRepository`/Mock을 주입한다.
final diaryRepositoryProvider = Provider<DiaryRepository>(
  (ref) => ApiDiaryRepository(ref.watch(dioProvider)),
);

/// 월별 작성 요약(캘린더 dot용). 인자는 'yyyy-MM' 형식의 연월.
final monthlySummaryProvider =
    FutureProvider.autoDispose.family<DiarySummary, String>((ref, yearMonth) {
  return ref.watch(diaryRepositoryProvider).getMonthlySummary(yearMonth);
});

/// 해당 월('yyyy-MM')의 기록 목록(목록 화면용). 하루 1기록이라 한 번에 로드한다.
///
/// 목록 화면이 이 프로바이더를 watch하므로, 작성/수정/삭제 후
/// `ref.invalidate(monthDiariesProvider)`만 호출하면 (탭 복귀 없이) 즉시 갱신된다.
final monthDiariesProvider =
    FutureProvider.autoDispose.family<List<Diary>, String>((ref, yearMonth) {
  return ref.watch(diaryRepositoryProvider).getMonthList(yearMonth);
});

/// id 기반 단건 조회(상세 화면용).
final diaryByIdProvider = FutureProvider.autoDispose.family<Diary, int>((ref, id) {
  return ref.watch(diaryRepositoryProvider).getById(id);
});

/// 날짜 기반 단건 조회(에디터 수정 모드 프리필용). 없으면 null.
final diaryByDateProvider =
    FutureProvider.autoDispose.family<Diary?, DateTime>((ref, date) {
  return ref.watch(diaryRepositoryProvider).getByDate(date);
});
