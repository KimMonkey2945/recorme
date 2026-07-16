// 캐릭터 홈 화면 테스트.
// - 선택 캐릭터의 이름·소개·Lv·코인·경험치 게이지 렌더.
// - 미확인 보상(unacked>0) 시 배지 숫자 노출.
// - 옷장 진입 버튼 존재.
// - 미선택(character==null) 시 빈 화면(가드가 온보딩으로 보내는 찰나).
//
// myCharacterProvider는 인증 상태를 타므로 저장소 직결로 override한다(wardrobe_test 패턴).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:record/core/theme/app_theme.dart';
import 'package:record/features/character/data/fake_character_repository.dart';
import 'package:record/features/character/domain/character.dart';
import 'package:record/features/character/domain/my_character.dart';
import 'package:record/features/character/domain/reward.dart';
import 'package:record/features/character/presentation/character_home_page.dart';
import 'package:record/features/character/presentation/providers/character_providers.dart';
import 'package:record/features/character/presentation/widgets/idle_character_view.dart';

/// 지정한 내 캐릭터를 **지연 없이** 즉시 돌려주는 저장소.
/// (기본 Fake는 300ms 지연이 있어, tagline용 charactersProvider가 즉시 정착하면
/// pumpAndSettle이 fetchMyCharacter 타이머를 기다리지 않고 리턴해 로딩 화면이 잡힌다.)
class _StubCharacterRepository extends FakeCharacterRepository {
  _StubCharacterRepository(this._my) : super(selectedCode: 'MONKEY');

  final MyCharacter _my;

  @override
  Future<MyCharacter> fetchMyCharacter() async => _my;

  // 홈 진입 시 출석 호출이 발생한다 — 지연 타이머 없이 즉시(미적립) 반환해 테스트를 결정적으로 유지한다
  // (기본 Fake의 300ms 타이머가 위젯 dispose 후에도 남아 실패하는 것 방지).
  @override
  Future<AttendanceResult> markAttendance() async =>
      const AttendanceResult(granted: false, coin: 0, balance: 0);
}

/// 선택 완료(기본값) 내 캐릭터.
const _selectedMonkey = MyCharacter(
  character: SelectedCharacter(
    code: 'MONKEY',
    nameKo: '원숭이',
    thumbnailUrl: 'assets/characters/monkey.png',
  ),
  coinBalance: 0,
  unackedRewardCount: 0,
);

/// 코인·보상 배지 검증용 — 풍부한 값.
const _richMonkey = MyCharacter(
  character: SelectedCharacter(
    code: 'MONKEY',
    nameKo: '원숭이',
    thumbnailUrl: 'assets/characters/monkey.png',
  ),
  coinBalance: 320,
  unackedRewardCount: 3,
);

/// 미선택(온보딩 대상) — character가 null.
const _unselected = MyCharacter(
  character: null,
  coinBalance: 0,
  unackedRewardCount: 0,
);

Widget _wrap(FakeCharacterRepository repo) => ProviderScope(
      overrides: [
        characterRepositoryProvider.overrideWithValue(repo),
        myCharacterProvider.overrideWith(
          (ref) => ref.watch(characterRepositoryProvider).fetchMyCharacter(),
        ),
        // 소개 문구용 캐러셀 목록 — 지연 없는 즉시값으로 주입한다
        // (autoDispose + Future.delayed 타이머가 pumpAndSettle 후에도 남아 실패하는 것 방지).
        charactersProvider.overrideWith(
          (ref) => const CharacterList(
            selectedCharacter: 'MONKEY',
            items: [
              Character(
                code: 'MONKEY',
                nameKo: '원숭이',
                tagline: '뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.',
                thumbnailUrl: 'assets/characters/monkey.png',
                owned: true,
                selected: true,
              ),
            ],
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const CharacterHomePage()),
    );

void main() {
  setUp(() => IdleCharacterView.debugDisableIdleAnimation = true);
  tearDown(() => IdleCharacterView.debugDisableIdleAnimation = false);

  Future<void> pumpHome(WidgetTester tester, FakeCharacterRepository repo) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repo));
  }

  testWidgets('선택 캐릭터: 이름·소개·코인·옷장 버튼 렌더', (tester) async {
    await pumpHome(tester, _StubCharacterRepository(_selectedMonkey));
    await tester.pumpAndSettle();

    // 이름 + 소개(캐러셀 tagline과 공유)
    expect(find.text('원숭이'), findsOneWidget);
    expect(find.textContaining('여유가 특기'), findsOneWidget);
    // 레벨/경험치는 제거됐다 — Lv 배지가 없어야 한다.
    expect(find.textContaining('Lv.'), findsNothing);
    // 옷장 진입 버튼
    expect(find.text('옷장'), findsOneWidget);
    expect(find.byIcon(Icons.checkroom), findsOneWidget);
  });

  testWidgets('미확인 보상 > 0 → 보상 배지에 개수 노출, 코인 잔액 표시', (tester) async {
    await pumpHome(tester, _StubCharacterRepository(_richMonkey));
    await tester.pumpAndSettle();

    expect(find.text('320'), findsOneWidget); // 코인 잔액
    // 보상 배지 안의 개수(3)
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets('미선택(character==null) → 빈 화면(옷장 버튼·이름 없음)', (tester) async {
    await pumpHome(tester, _StubCharacterRepository(_unselected));
    await tester.pumpAndSettle();

    expect(find.text('옷장'), findsNothing);
    expect(find.text('원숭이'), findsNothing);
  });

  testWidgets('보상 배지 탭 → 보상함(/rewards)으로 이동', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CharacterHomePage()),
        GoRoute(
          path: '/rewards',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('보상함 화면'))),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        characterRepositoryProvider
            .overrideWithValue(_StubCharacterRepository(_richMonkey)),
        myCharacterProvider.overrideWith(
          (ref) => ref.watch(characterRepositoryProvider).fetchMyCharacter(),
        ),
        charactersProvider.overrideWith(
          (ref) => const CharacterList(selectedCharacter: 'MONKEY', items: []),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // 상태바의 보상 배지(선물 아이콘 IconButton) 탭.
    await tester.tap(find.byIcon(Icons.card_giftcard_outlined));
    await tester.pumpAndSettle();

    expect(find.text('보상함 화면'), findsOneWidget);
  });
}
