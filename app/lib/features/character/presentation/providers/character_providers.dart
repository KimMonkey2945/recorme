import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/api_character_repository.dart';
import '../../data/fake_character_repository.dart';
import '../../domain/character.dart';
import '../../domain/character_repository.dart';
import '../../domain/item_group.dart';
import '../../domain/my_character.dart';
import '../../domain/reward.dart';

/// 웹 UI 프리뷰/수동 확인용 스위치.
///
/// `--dart-define=USE_FAKE_CHARACTER_REPO=true`면 백엔드 없이 [FakeCharacterRepository]로
/// 동작한다(기본 false → 실제 API). 릴리스 빌드에는 영향 없다.
const bool useFakeCharacterRepo =
    bool.fromEnvironment('USE_FAKE_CHARACTER_REPO');

/// 캐릭터 저장소 주입 지점.
///
/// 기본은 실제 API 구현([ApiCharacterRepository]).
/// 테스트에서는 `ProviderScope(overrides: [...])`로 Fake/Mock을 주입한다.
final characterRepositoryProvider = Provider<CharacterRepository>((ref) {
  if (useFakeCharacterRepo) return FakeCharacterRepository();
  return ApiCharacterRepository(ref.watch(dioProvider));
});

/// 선택 가능한 캐릭터 목록(온보딩 캐러셀용).
final charactersProvider = FutureProvider.autoDispose<CharacterList>((ref) {
  return ref.watch(characterRepositoryProvider).fetchCharacters();
});

/// 내 캐릭터 상태. **라우터의 온보딩 가드가 구독하므로 autoDispose를 쓰지 않는다.**
///
/// 미인증 상태에서는 조회하지 않고 null을 돌려준다(로그인 전 불필요한 401 호출 방지).
/// 인증되면 `GET /characters/me`를 호출하며, 미선택자는 `character == null`인
/// [MyCharacter]가 온다(404가 아니다) → 이것이 온보딩 신호다.
///
/// 반환 타입이 nullable인 이유:
/// - `null`      : 아직 조회 대상이 아님(미인증) → 가드는 아무 판단도 하지 않는다.
/// - `character == null` : 인증됐고 캐릭터 미선택 → 온보딩으로 보낸다.
final myCharacterProvider = FutureProvider<MyCharacter?>((ref) async {
  // Fake 모드(웹 프리뷰)는 인증 없이도 조회한다 — 백엔드 없이 온보딩·옷장을 확인하는 용도.
  if (!useFakeCharacterRepo) {
    final status = ref.watch(authControllerProvider);
    if (status != AuthStatus.authenticated) return null;
  }
  return ref.watch(characterRepositoryProvider).fetchMyCharacter();
});

/// 캐릭터 선택 제출 상태(로딩/에러)를 담당한다.
///
/// 전역 상태와 분리해 제출의 진행/실패만 표현한다(CreateResolutionController 관례).
/// 에러는 [Failure](한국어 메시지)로 전파하고, 성공 시 관련 provider를 invalidate한다.
class SelectCharacterController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 캐릭터 선택 제출. 성공 시 갱신된 [MyCharacter]를 돌려준다.
  Future<MyCharacter> submit(String code) async {
    state = const AsyncLoading();
    try {
      final updated =
          await ref.read(characterRepositoryProvider).selectCharacter(code);
      state = const AsyncData(null);
      // 내 캐릭터(온보딩 가드가 구독)·목록을 갱신한다.
      ref.invalidate(myCharacterProvider);
      ref.invalidate(charactersProvider);
      return updated;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final selectCharacterControllerProvider =
    AsyncNotifierProvider<SelectCharacterController, void>(
        SelectCharacterController.new);

/// 아이템 그룹 전체 목록(옷장·상점 공용).
///
/// 슬롯 필터는 서버가 아니라 화면에서 한다 — 옷장의 slot 탭 전환마다 왕복하지 않고
/// 한 번 받아 6개 탭이 나눠 쓴다. 착용/구매 후에는 invalidate로 갱신한다.
final wardrobeItemsProvider =
    FutureProvider.autoDispose<List<ItemGroup>>((ref) {
  return ref.watch(characterRepositoryProvider).fetchItems();
});

/// 착용 배치 교체 제출 상태(로딩/에러)를 담당한다.
///
/// [SelectCharacterController]와 같은 관례 — 성공 시 내 캐릭터(홈·스테이지가 구독)와
/// 아이템 목록(equipped 플래그)을 invalidate한다.
class ReplaceEquipmentController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 착용 전체 스냅샷을 제출한다. 성공 시 갱신된 [MyCharacter]를 돌려준다.
  Future<MyCharacter> submit(List<EquipmentSelection> equipment) async {
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(characterRepositoryProvider)
          .replaceEquipment(equipment);
      state = const AsyncData(null);
      ref.invalidate(myCharacterProvider);
      ref.invalidate(wardrobeItemsProvider);
      return updated;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final replaceEquipmentControllerProvider =
    AsyncNotifierProvider<ReplaceEquipmentController, void>(
        ReplaceEquipmentController.new);

// ── 보상함 · 리액션 · 출석(Task 028 연동) ──────────────────────────

/// 보상함 무한 스크롤 상태(누적 items + 커서 + 추가 로딩 플래그). [FeedState] 관례.
class RewardsState {
  const RewardsState({
    this.items = const [],
    this.hasNext = false,
    this.nextCursor,
    this.isLoadingMore = false,
  });

  final List<Reward> items;
  final bool hasNext;
  final int? nextCursor;
  final bool isLoadingMore;

  RewardsState copyWith({
    List<Reward>? items,
    bool? hasNext,
    int? nextCursor,
    bool? isLoadingMore,
  }) =>
      RewardsState(
        items: items ?? this.items,
        hasNext: hasNext ?? this.hasNext,
        nextCursor: nextCursor ?? this.nextCursor,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

/// 미확인 보상함 Notifier. 첫 페이지 로드 + 하단 근접 시 loadMore(커서 누적). [FeedNotifier] 미러.
class RewardsNotifier extends AsyncNotifier<RewardsState> {
  static const int _pageSize = 20;

  CharacterRepository get _repo => ref.read(characterRepositoryProvider);

  @override
  Future<RewardsState> build() async {
    final page = await _repo.fetchRewards(size: _pageSize);
    return RewardsState(
      items: page.items,
      hasNext: page.hasNext,
      nextCursor: page.nextCursor,
    );
  }

  /// 다음 페이지를 이어 붙인다. 더 없거나 이미 로딩 중이면 무시.
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null ||
        !current.hasNext ||
        current.isLoadingMore ||
        current.nextCursor == null) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page =
          await _repo.fetchRewards(cursor: current.nextCursor, size: _pageSize);
      state = AsyncData(current.copyWith(
        items: [...current.items, ...page.items],
        hasNext: page.hasNext,
        nextCursor: page.nextCursor,
        isLoadingMore: false,
      ));
    } catch (_) {
      // 추가 로딩 실패 시 로딩 플래그만 해제(다음 스크롤에서 재시도 가능).
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// 당겨서 새로고침 — 첫 페이지부터 다시 로드.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final rewardsProvider =
    AsyncNotifierProvider.autoDispose<RewardsNotifier, RewardsState>(
        RewardsNotifier.new);

/// 보상 확인(ack) 제출 상태. 성공 시 홈 배지(내 캐릭터)와 보상함을 invalidate한다.
class AckRewardsController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 미확인 보상 전체 확인. 확인된 개수를 돌려준다.
  Future<int> ack() async {
    state = const AsyncLoading();
    try {
      final acked = await ref.read(characterRepositoryProvider).ackRewards();
      state = const AsyncData(null);
      ref.invalidate(myCharacterProvider); // 홈 미확인 배지 감소
      ref.invalidate(rewardsProvider); // 보상함 비우기
      return acked;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final ackRewardsControllerProvider =
    AsyncNotifierProvider<AckRewardsController, void>(AckRewardsController.new);

/// 출석 적립 컨트롤러. 홈 진입 시 1회 호출한다. 성공(granted)이면 내 캐릭터를 invalidate해
/// 코인·미확인 배지가 갱신되게 한다. 실패는 조용히 흡수한다(출석은 부가 기능 — 홈 진입을 막지 않는다).
class AttendanceController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 출석 도장. 이번에 적립됐으면 [AttendanceResult](granted=true)를, 아니면 granted=false를 돌려준다.
  /// 네트워크 실패 시 null을 돌려주고 조용히 넘어간다.
  Future<AttendanceResult?> mark() async {
    try {
      final result = await ref.read(characterRepositoryProvider).markAttendance();
      if (result.granted) {
        ref.invalidate(myCharacterProvider);
      }
      return result;
    } on Object {
      // 출석 적립 실패는 홈 표시를 막지 않는다(코인은 백스톱 폴러가 보정하지 않지만,
      // 출석은 다음 진입에서 재시도된다).
      return null;
    }
  }
}

final attendanceControllerProvider =
    AsyncNotifierProvider<AttendanceController, void>(AttendanceController.new);

/// 아이템 구매(코인 소비) 제출 상태. 성공 시 내 캐릭터(홈 코인·소유)와 옷장 목록을 invalidate 한다.
/// [SelectCharacterController] 관례 — 실패(COIN_INSUFFICIENT/FEATURE_DISABLED)는 [Failure]로 rethrow 해 UI가 처리한다.
class PurchaseController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 아이템 구매 제출. 성공 시 갱신된 [MyCharacter]를 돌려준다(잔액·소유 반영).
  Future<MyCharacter> purchase(String groupCode) async {
    state = const AsyncLoading();
    try {
      final updated =
          await ref.read(characterRepositoryProvider).purchaseItem(groupCode);
      state = const AsyncData(null);
      ref.invalidate(myCharacterProvider); // 홈 코인 잔액
      ref.invalidate(wardrobeItemsProvider); // 옷장 소유/잠금 상태
      return updated;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final purchaseControllerProvider =
    AsyncNotifierProvider<PurchaseController, void>(PurchaseController.new);
