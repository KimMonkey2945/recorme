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
