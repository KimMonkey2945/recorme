import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dto/diary_dto.dart';
import '../../data/fake_diary_repository.dart';
import '../../domain/diary_repository.dart';

/// 일기 저장소 주입 지점.
///
/// Phase 2: 인메모리 더미([FakeDiaryRepository]).
/// Phase 3: 실제 API 구현으로 이 provider만 교체하면 화면 코드는 그대로 동작한다.
/// 테스트에서는 `ProviderScope(overrides: [...])`로 Fake/Mock을 주입한다.
final diaryRepositoryProvider = Provider<DiaryRepository>(
  (ref) => FakeDiaryRepository(),
);

/// 월별 작성 요약(캘린더 dot용). 인자는 'yyyy-MM' 형식의 연월.
final monthlySummaryProvider =
    FutureProvider.family<DiarySummary, String>((ref, yearMonth) {
  return ref.watch(diaryRepositoryProvider).getMonthlySummary(yearMonth);
});

/// id 기반 단건 조회(상세 화면용).
final diaryByIdProvider = FutureProvider.family<Diary, int>((ref, id) {
  return ref.watch(diaryRepositoryProvider).getById(id);
});

/// 날짜 기반 단건 조회(에디터 수정 모드 프리필용). 없으면 null.
final diaryByDateProvider =
    FutureProvider.family<Diary?, DateTime>((ref, date) {
  return ref.watch(diaryRepositoryProvider).getByDate(date);
});
