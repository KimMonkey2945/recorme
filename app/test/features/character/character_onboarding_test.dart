// 캐릭터 선택 온보딩 화면 테스트.
// - 캐릭터 2종 카드 렌더(이름·tagline), 캐러셀 스와이프, 인디케이터 도트.
// - "선택" 탭 → selectCharacter 호출 + '/'로 이동.
// - 선택 API 실패 → 에러 스낵바 + 온보딩 유지(홈으로 새지 않음).
// - 로딩/에러 상태 렌더.
//
// 네트워크 없이 characterRepositoryProvider를 Fake로 override해 검증한다.
//
// ⚠️ idle 애니메이션은 무한 반복이라 pumpAndSettle()을 영원히 멈추지 않게 만든다.
//    → setUp에서 IdleCharacterView.debugDisableIdleAnimation을 켜 hang을 막는다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:record/core/error/failure.dart';
import 'package:record/core/router/app_router.dart';
import 'package:record/core/theme/app_colors.dart';
import 'package:record/core/theme/app_theme.dart';
import 'package:record/features/character/domain/character.dart';
import 'package:record/features/character/domain/character_repository.dart';
import 'package:record/features/character/domain/my_character.dart';
import 'package:record/features/character/presentation/character_onboarding_page.dart';
import 'package:record/features/character/presentation/providers/character_providers.dart';
import 'package:record/features/character/presentation/widgets/idle_character_view.dart';
import 'package:record/shared/widgets/error_view.dart';
import 'package:record/shared/widgets/loading_view.dart';

/// 결정적 테스트용 가짜 CharacterRepository.
class _FakeCharacterRepository implements CharacterRepository {
  _FakeCharacterRepository({
    this.failOnFetch = false,
    this.failOnSelect = false,
  });

  final bool failOnFetch;
  final bool failOnSelect;

  /// selectCharacter로 전달된 코드(호출 검증용).
  String? selectedCode;
  int selectCallCount = 0;

  static const _monkey = Character(
    code: 'MONKEY',
    nameKo: '원숭이',
    tagline: '뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.',
    thumbnailUrl: 'assets/characters/monkey.png',
    owned: true,
    selected: false,
  );

  static const _redPanda = Character(
    code: 'RED_PANDA',
    nameKo: '레서판다',
    tagline: '부지런히 곁을 지켜요. 정 많고 애착이 강한 친구예요.',
    thumbnailUrl: 'assets/characters/red_panda.png',
    owned: true,
    selected: false,
  );

  @override
  Future<CharacterList> fetchCharacters() async {
    if (failOnFetch) {
      throw const Failure('NETWORK_ERROR', '캐릭터 목록을 불러오지 못했어요.');
    }
    return const CharacterList(
      selectedCharacter: null,
      items: [_monkey, _redPanda],
    );
  }

  @override
  Future<MyCharacter> fetchMyCharacter() async => const MyCharacter(
        character: null,
        level: 1,
        exp: 0,
        expToNext: 100,
        coinBalance: 0,
        unackedRewardCount: 0,
      );

  @override
  Future<MyCharacter> selectCharacter(String code) async {
    selectCallCount++;
    selectedCode = code;
    if (failOnSelect) {
      throw const Failure('CHARACTER_NOT_OWNED', '아직 보유하지 않은 캐릭터예요.');
    }
    return MyCharacter(
      character: SelectedCharacter(
        code: code,
        nameKo: code == 'MONKEY' ? '원숭이' : '레서판다',
        thumbnailUrl: 'assets/characters/monkey.png',
      ),
      level: 1,
      exp: 0,
      expToNext: 100,
      coinBalance: 0,
      unackedRewardCount: 0,
    );
  }
}

/// 온보딩 → 메인('/') 이동을 검증하기 위한 최소 라우터.
/// 앱 라우터를 건드리지 않고 `context.go('/')` 동작만 확인한다.
Widget _wrap(CharacterRepository repo) {
  final router = GoRouter(
    initialLocation: characterOnboardingRoute,
    routes: [
      GoRoute(
        path: characterOnboardingRoute,
        builder: (context, state) => const CharacterOnboardingPage(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('메인 캘린더'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [characterRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light,
    ),
  );
}

/// peek로 살짝 보이는 **오른쪽 카드**를 탭한다.
///
/// 카드의 대부분은 뷰포트 밖이라 `find.text('레서판다')`의 중심 좌표는 화면을 벗어난다
/// (탭이 아무 데도 닿지 않는다). 그래서 화면에 실제로 보이는 오른쪽 끝을 좌표로 탭한다.
Future<void> _tapPeekCardOnRight(WidgetTester tester) async {
  final pageRect = tester.getRect(find.byType(PageView));
  await tester.tapAt(Offset(pageRect.right - 12, pageRect.center.dy));
  await tester.pumpAndSettle();
}

/// 도트의 배경색(활성 여부 판정용).
/// 키는 탭 타깃인 GestureDetector에 붙어 있으므로 그 하위의 AnimatedContainer를 찾는다.
Color _dotColor(WidgetTester tester, int index) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(ValueKey('character-dot-$index')),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  setUp(() {
    // 무한 idle 애니메이션을 꺼 pumpAndSettle 타임아웃을 방지한다.
    IdleCharacterView.debugDisableIdleAnimation = true;
  });

  tearDown(() {
    IdleCharacterView.debugDisableIdleAnimation = false;
  });

  group('CharacterOnboardingPage 렌더', () {
    testWidgets('로딩 상태 → LoadingView', (tester) async {
      await tester.pumpWidget(_wrap(_FakeCharacterRepository()));

      // 첫 프레임: 아직 목록 미도착.
      expect(find.byType(LoadingView), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(LoadingView), findsNothing);
    });

    testWidgets('목록 조회 실패 → ErrorView', (tester) async {
      await tester.pumpWidget(
        _wrap(_FakeCharacterRepository(failOnFetch: true)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('캐릭터 목록을 불러오지 못했어요.'), findsOneWidget);
    });

    testWidgets('캐릭터 2종 카드 렌더(이름) + 헤드라인 / tagline 미노출', (tester) async {
      await tester.pumpWidget(_wrap(_FakeCharacterRepository()));
      await tester.pumpAndSettle();

      expect(find.text('기억을 같이 만들어갈\n친구를 선택해주세요.'), findsOneWidget);

      // 이름
      expect(find.text('원숭이'), findsOneWidget);
      expect(find.text('레서판다'), findsOneWidget);

      // tagline(성격 소개)은 렌더하지 않는다 — 화면을 캐릭터에 집중시킨다.
      expect(
        find.text('뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.'),
        findsNothing,
      );
      expect(
        find.text('부지런히 곁을 지켜요. 정 많고 애착이 강한 친구예요.'),
        findsNothing,
      );

      // 하단 보조 문구
      expect(
        find.text('캐릭터 꾸미기 메뉴에서\n마음에 드는 모습으로 변경할 수 있어요.'),
        findsOneWidget,
      );
    });

    testWidgets('인디케이터 도트는 캐릭터 수만큼, 초기 활성은 0번', (tester) async {
      await tester.pumpWidget(_wrap(_FakeCharacterRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('character-dot-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('character-dot-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('character-dot-2')), findsNothing);

      expect(_dotColor(tester, 0), AppColors.primary);
      expect(_dotColor(tester, 1), AppColors.hairline);
    });

    testWidgets('캐러셀 스와이프로 페이지 전환 → 활성 도트 이동', (tester) async {
      await tester.pumpWidget(_wrap(_FakeCharacterRepository()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(_dotColor(tester, 0), AppColors.hairline);
      expect(_dotColor(tester, 1), AppColors.primary);
    });

    testWidgets('옆 카드(레서판다) 탭 → 중앙으로 이동 + 활성 도트 이동', (tester) async {
      await tester.pumpWidget(_wrap(_FakeCharacterRepository()));
      await tester.pumpAndSettle();

      await _tapPeekCardOnRight(tester);

      expect(_dotColor(tester, 0), AppColors.hairline);
      expect(_dotColor(tester, 1), AppColors.primary);
    });

    testWidgets('IdleCharacterView가 애니메이션 정지 상태에서 예외 없이 렌더된다', (tester) async {
      // 메시 워프 렌더러는 raw ui.Image가 있어야 동작한다. 테스트 환경에는 없으므로
      // Image.asset 폴백 경로를 타야 하고, 이 경로에서 Ticker·예외가 없어야 한다.
      await tester.pumpWidget(_wrap(_FakeCharacterRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(IdleCharacterView), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('도트 탭 → 해당 캐릭터로 이동', (tester) async {
      await tester.pumpWidget(_wrap(_FakeCharacterRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('character-dot-1')));
      await tester.pumpAndSettle();

      expect(_dotColor(tester, 1), AppColors.primary);

      // 다시 0번 도트로 돌아온다.
      await tester.tap(find.byKey(const ValueKey('character-dot-0')));
      await tester.pumpAndSettle();

      expect(_dotColor(tester, 0), AppColors.primary);
    });
  });

  group('캐릭터 선택 제출', () {
    testWidgets('"선택" 탭 → selectCharacter(중앙 카드 코드) 호출 후 "/"로 이동',
        (tester) async {
      final repo = _FakeCharacterRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '선택'));
      await tester.pumpAndSettle();

      expect(repo.selectCallCount, 1);
      expect(repo.selectedCode, 'MONKEY'); // 초기 중앙 카드
      // 메인으로 이동했다.
      expect(find.text('메인 캘린더'), findsOneWidget);
      expect(find.byType(CharacterOnboardingPage), findsNothing);
    });

    testWidgets('스와이프 후 "선택" → 두 번째 캐릭터 코드로 호출', (tester) async {
      final repo = _FakeCharacterRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '선택'));
      await tester.pumpAndSettle();

      expect(repo.selectedCode, 'RED_PANDA');
      expect(find.text('메인 캘린더'), findsOneWidget);
    });

    testWidgets('옆 카드 탭 후 "선택" → RED_PANDA로 호출', (tester) async {
      final repo = _FakeCharacterRepository();
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      await _tapPeekCardOnRight(tester);

      await tester.tap(find.widgetWithText(FilledButton, '선택'));
      await tester.pumpAndSettle();

      expect(repo.selectedCode, 'RED_PANDA');
      expect(find.text('메인 캘린더'), findsOneWidget);
    });

    testWidgets('선택 API 실패 → 에러 스낵바 + 온보딩 유지(홈으로 새지 않음)', (tester) async {
      final repo = _FakeCharacterRepository(failOnSelect: true);
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '선택'));
      await tester.pump(); // 제출 시작
      await tester.pump(); // 실패 → 스낵바

      expect(repo.selectCallCount, 1);
      expect(find.text('아직 보유하지 않은 캐릭터예요.'), findsOneWidget);
      // 온보딩 화면에 그대로 머문다.
      expect(find.byType(CharacterOnboardingPage), findsOneWidget);
      expect(find.text('메인 캘린더'), findsNothing);

      // 스낵바 타이머 정리.
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });
}
