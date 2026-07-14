// 캐릭터 온보딩 리다이렉트 가드 테스트.
// - character == null(미선택) → /onboarding/character 로 유도.
// - 온보딩 화면 자체는 리다이렉트 루프에 빠지지 않는다.
// - 선택 완료 후에는 일반 경로에서 리다이렉트가 없다.
// - 미인증/로딩/에러(판단 불가)에는 분기를 보류한다.
// - 기존 탭 브랜치 순서 회귀 없음(캘린더 index 0 유지 — FCM 딥링크 보호).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:record/core/router/app_router.dart';
import 'package:record/features/auth/presentation/providers/auth_provider.dart';
import 'package:record/features/character/data/fake_character_repository.dart';
import 'package:record/features/character/domain/my_character.dart';
import 'package:record/features/character/presentation/providers/character_providers.dart';

/// 미선택 상태(온보딩 필요).
const _unselected = MyCharacter(
  character: null,
  level: 1,
  exp: 0,
  expToNext: 100,
  coinBalance: 0,
  unackedRewardCount: 0,
);

/// 선택 완료 상태.
const _selected = MyCharacter(
  character: SelectedCharacter(
    code: 'MONKEY',
    nameKo: '원숭이',
    thumbnailUrl: 'assets/characters/monkey.png',
    riveArtboard: 'monkey',
  ),
  level: 1,
  exp: 0,
  expToNext: 100,
  coinBalance: 0,
  unackedRewardCount: 0,
);

/// Supabase 없이 인증 상태를 고정하는 가짜 AuthController.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this.status);

  final AuthStatus status;

  @override
  AuthStatus build() => status;
}

void main() {
  group('characterOnboardingRedirect (순수 가드)', () {
    test('미선택 + 일반 경로 → 온보딩으로 유도', () {
      expect(
        characterOnboardingRedirect(myCharacter: _unselected, location: '/'),
        characterOnboardingRoute,
      );
      expect(
        characterOnboardingRedirect(
          myCharacter: _unselected,
          location: '/resolution',
        ),
        characterOnboardingRoute,
      );
    });

    test('미선택 + 이미 온보딩 → 리다이렉트 없음(루프 방지)', () {
      expect(
        characterOnboardingRedirect(
          myCharacter: _unselected,
          location: characterOnboardingRoute,
        ),
        isNull,
      );
    });

    test('선택 완료 → 일반 경로에서 리다이렉트 없음', () {
      expect(
        characterOnboardingRedirect(myCharacter: _selected, location: '/'),
        isNull,
      );
      expect(
        characterOnboardingRedirect(myCharacter: _selected, location: '/list'),
        isNull,
      );
    });

    test('선택 완료 후 온보딩 재진입 → 메인으로', () {
      expect(
        characterOnboardingRedirect(
          myCharacter: _selected,
          location: characterOnboardingRoute,
        ),
        '/',
      );
    });

    test('판단 불가(미인증·로딩·에러) → 분기 보류(null)', () {
      expect(
        characterOnboardingRedirect(myCharacter: null, location: '/'),
        isNull,
      );
      expect(
        characterOnboardingRedirect(
          myCharacter: null,
          location: characterOnboardingRoute,
        ),
        isNull,
      );
    });
  });

  group('routerProvider 구성', () {
    /// Supabase/네트워크 없이 라우터를 만든다.
    GoRouter buildRouter(AuthStatus status) {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(status)),
          characterRepositoryProvider
              .overrideWithValue(FakeCharacterRepository()),
        ],
      );
      addTearDown(container.dispose);
      return container.read(routerProvider);
    }

    test('온보딩 라우트가 등록돼 있다', () {
      final router = buildRouter(AuthStatus.authenticated);
      final paths = router.configuration.routes
          .whereType<GoRoute>()
          .map((r) => r.path)
          .toList();

      expect(paths, contains(characterOnboardingRoute));
    });

    test('기존 탭 브랜치 순서 회귀 없음(캘린더 index 0 유지)', () {
      final router = buildRouter(AuthStatus.authenticated);
      final shell = router.configuration.routes
          .whereType<StatefulShellRoute>()
          .single;

      final branchPaths = shell.branches
          .map((b) => (b.routes.first as GoRoute).path)
          .toList();

      // FCM 딥링크가 인덱스에 의존하므로 순서를 절대 바꾸지 않는다.
      expect(branchPaths, ['/', '/list', '/resolution', '/feed']);
    });
  });
}
