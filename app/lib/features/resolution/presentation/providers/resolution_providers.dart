import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/api_resolution_repository.dart';
import '../../domain/resolution.dart';
import '../../domain/resolution_repository.dart';

/// 결심 저장소 주입 지점.
///
/// 실제 API 구현([ApiResolutionRepository])을 주입한다.
/// 테스트에서는 `ProviderScope(overrides: [...])`로 `FakeResolutionRepository`/Mock을 주입한다.
final resolutionRepositoryProvider = Provider<ResolutionRepository>(
  (ref) => ApiResolutionRepository(ref.watch(dioProvider)),
);

/// 내 결심 목록(탭별). 인자는 상태 필터([ResolutionStatus]), null이면 전체.
///
/// 목록 화면이 이 프로바이더를 watch하므로, 생성/완료/연장/취소 후
/// `ref.invalidate(resolutionListProvider)`만 호출하면 즉시 갱신된다.
/// (첫 페이지만 로드한다. 추가 페이지가 필요하면 커서 페이징을 별도 구성한다.)
final resolutionListProvider = FutureProvider.autoDispose
    .family<List<ResolutionSummaryItem>, ResolutionStatus?>((ref, status) async {
  final page = await ref.watch(resolutionRepositoryProvider).getList(status);
  return page.items;
});

/// id 기반 단건 상세(상세 화면용).
final resolutionByIdProvider =
    FutureProvider.autoDispose.family<Resolution, int>((ref, id) {
  return ref.watch(resolutionRepositoryProvider).getById(id);
});

/// 월별 캘린더((날짜 × 결심)당 1행). 인자는 'yyyy-MM' 형식의 연월.
final resolutionCalendarProvider = FutureProvider.autoDispose
    .family<List<ResolutionCalendarDay>, String>((ref, yearMonth) {
  return ref.watch(resolutionRepositoryProvider).getCalendar(yearMonth);
});

/// 결심 생성 폼의 제출 상태(로딩/에러)를 담당한다.
///
/// 전역 목록/캘린더와 분리해 폼 제출의 진행/실패만 표현한다(EmailAuthController 관례).
/// 에러는 [Failure](한국어 메시지)로 전파하고, 성공 시 관련 provider를 invalidate한다.
class CreateResolutionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 결심 생성 제출. 성공 시 생성된 [Resolution]을 돌려준다.
  Future<Resolution> submit({
    required String title,
    required DateTime startDate,
    String? reminderTime,
  }) async {
    state = const AsyncLoading();
    try {
      final created = await ref.read(resolutionRepositoryProvider).create(
            title: title,
            startDate: startDate,
            reminderTime: reminderTime,
          );
      state = const AsyncData(null);
      // 목록·캘린더를 갱신한다.
      ref.invalidate(resolutionListProvider);
      ref.invalidate(resolutionCalendarProvider);
      return created;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final createResolutionControllerProvider =
    AsyncNotifierProvider<CreateResolutionController, void>(
        CreateResolutionController.new);

/// 오늘자 완료 체크 제출 상태(로딩/에러)를 담당한다.
class CompleteTodayController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 오늘자 완료 체크 제출. 성공 시 갱신된 [Resolution]을 돌려준다.
  Future<Resolution> submit(int id) async {
    state = const AsyncLoading();
    try {
      final updated =
          await ref.read(resolutionRepositoryProvider).completeToday(id);
      state = const AsyncData(null);
      // 상세·목록·캘린더를 갱신한다.
      ref.invalidate(resolutionByIdProvider(id));
      ref.invalidate(resolutionListProvider);
      ref.invalidate(resolutionCalendarProvider);
      return updated;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final completeTodayControllerProvider =
    AsyncNotifierProvider<CompleteTodayController, void>(
        CompleteTodayController.new);

/// 결심 연장 제출 상태(로딩/에러)를 담당한다.
class ExtendController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 결심 연장 제출. 성공 시 새로 생성된 다음 3일 [Resolution]을 돌려준다.
  Future<Resolution> submit(int id, {String? reminderTime}) async {
    state = const AsyncLoading();
    try {
      final created = await ref
          .read(resolutionRepositoryProvider)
          .extend(id, reminderTime: reminderTime);
      state = const AsyncData(null);
      // 이전 결심 상세(연장 상태 변화)·목록·캘린더를 갱신한다.
      ref.invalidate(resolutionByIdProvider(id));
      ref.invalidate(resolutionListProvider);
      ref.invalidate(resolutionCalendarProvider);
      return created;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final extendControllerProvider =
    AsyncNotifierProvider<ExtendController, void>(ExtendController.new);
