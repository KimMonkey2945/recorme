// 리액션 오버레이(F031) 위젯 테스트.
// - 서버 대사 + 코인 획득 카드 렌더.
// - 획득이 없어도(coin 0·line null) 캐릭터별 기본 대사 1줄은 항상 표시(빈손 리액션 금지).
// - reaction=null 이어도 캐릭터 성격별 기본 대사 표시(원숭이 느긋 / 레서판다 애쓰는).
// - '확인' 버튼·배경 탭 → onDismiss 호출.
//
// ⚠️ CharacterStage가 IdleCharacterView(무한 idle 애니메이션)를 쓰므로 pumpAndSettle hang 방지를 위해
//    debugDisableIdleAnimation을 켠다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/core/theme/app_theme.dart';
import 'package:record/features/character/domain/my_character.dart';
import 'package:record/features/character/domain/reward.dart';
import 'package:record/features/character/presentation/widgets/idle_character_view.dart';
import 'package:record/features/character/presentation/widgets/reaction_overlay.dart';

const _monkey = SelectedCharacter(
  code: 'MONKEY',
  nameKo: '원숭이',
  thumbnailUrl: 'assets/characters/monkey.png',
);
const _redPanda = SelectedCharacter(
  code: 'RED_PANDA',
  nameKo: '레서판다',
  thumbnailUrl: 'assets/characters/red_panda.png',
);

Reward _reward({int coin = 10, String? line = '오늘도 잘 마무리했네.'}) => Reward(
      id: 1,
      eventType: 'DIARY_CONFIRM',
      coinDelta: coin,
      balanceAfter: 100,
      line: line,
      context: 'CONFIRM',
      createdAt: DateTime(2026, 7, 16),
    );

Widget _wrap({
  required SelectedCharacter character,
  required Reward? reaction,
  required VoidCallback onDismiss,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        // ReactionOverlay는 Positioned.fill 이라 Stack 안에 놓는다.
        body: Stack(
          children: [
            ReactionOverlay(
              character: character,
              equipment: const [],
              reaction: reaction,
              onDismiss: onDismiss,
            ),
          ],
        ),
      ),
    );

void main() {
  setUp(() => IdleCharacterView.debugDisableIdleAnimation = true);
  tearDown(() => IdleCharacterView.debugDisableIdleAnimation = false);

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  testWidgets('서버 대사 + 코인 획득 카드 렌더', (tester) async {
    await pump(
      tester,
      _wrap(
        character: _monkey,
        reaction: _reward(coin: 10, line: '오늘도 잘 마무리했네.'),
        onDismiss: () {},
      ),
    );

    expect(find.text('오늘도 잘 마무리했네.'), findsOneWidget);
    expect(find.text('코인 +10'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
  });

  testWidgets('획득 없어도(coin 0·line null) 기본 대사 1줄은 항상 표시(빈손 금지)',
      (tester) async {
    await pump(
      tester,
      _wrap(
        character: _monkey,
        reaction: _reward(coin: 0, line: null),
        onDismiss: () {},
      ),
    );

    // 코인 카드는 없다(획득 0).
    expect(find.textContaining('코인 +'), findsNothing);
    // 원숭이 기본 대사(느긋한 말투)는 항상 있다.
    expect(find.textContaining('천천히 해도'), findsOneWidget);
  });

  testWidgets('reaction=null 이어도 캐릭터별 기본 대사 표시(레서판다 애쓰는 말투)',
      (tester) async {
    await pump(
      tester,
      _wrap(character: _redPanda, reaction: null, onDismiss: () {}),
    );

    expect(find.textContaining('이 기세로 내일도'), findsOneWidget);
  });

  testWidgets('확인 버튼 탭 → onDismiss 호출', (tester) async {
    var dismissed = false;
    await pump(
      tester,
      _wrap(
        character: _monkey,
        reaction: _reward(),
        onDismiss: () => dismissed = true,
      ),
    );

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('배경(스크림) 탭 → onDismiss 호출', (tester) async {
    var count = 0;
    await pump(
      tester,
      _wrap(
        character: _monkey,
        reaction: _reward(),
        onDismiss: () => count++,
      ),
    );

    // 좌상단 빈 스크림 영역 탭(중앙 카드 밖).
    await tester.tapAt(const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(count, greaterThanOrEqualTo(1));
  });
}
