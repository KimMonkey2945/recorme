// 감정 입력 위젯(Task 025) 테스트.
// - 프리셋 6종 렌더 · 선택/재탭 해제 · 콜백값
// - 직접 입력 모드 · 텍스트 → emotionLabel · 20자 제한 · 최근 추천 칩
// - 프리셋 ↔ 직접 입력 상호 배타

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/diary/presentation/widgets/emotion_input_section.dart';

void main() {
  /// (emotion, emotionLabel) 마지막 콜백값을 캡처하며 위젯을 펌프한다.
  Future<List<String?>> pump(
    WidgetTester tester, {
    List<String> recent = const [],
    String? initialEmotion,
    String? initialEmotionLabel,
  }) async {
    final captured = <String?>[null, null]; // [emotion, emotionLabel]
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EmotionInputSection(
            recentLabels: recent,
            initialEmotion: initialEmotion,
            initialEmotionLabel: initialEmotionLabel,
            onChanged: (e, l) {
              captured[0] = e;
              captured[1] = l;
            },
          ),
        ),
      ),
    ));
    return captured;
  }

  testWidgets('프리셋 6종 렌더 + 선택 시 콜백 + 재탭 해제', (tester) async {
    final captured = await pump(tester);

    // 프리셋 6종 칩 렌더.
    expect(find.text('😊 기쁨'), findsOneWidget);
    expect(find.text('😢 슬픔'), findsOneWidget);
    expect(find.text('😠 분노'), findsOneWidget);
    expect(find.text('😌 평온'), findsOneWidget);
    expect(find.text('😟 불안'), findsOneWidget);
    expect(find.text('🙂 무던'), findsOneWidget);

    // 기쁨 선택 → emotion=JOY, emotionLabel=null.
    await tester.tap(find.text('😊 기쁨'));
    await tester.pump();
    expect(captured[0], 'JOY');
    expect(captured[1], isNull);

    // 재탭 → 해제(둘 다 null).
    await tester.tap(find.text('😊 기쁨'));
    await tester.pump();
    expect(captured[0], isNull);
    expect(captured[1], isNull);
  });

  testWidgets('직접 입력 → 텍스트가 emotionLabel에 실림', (tester) async {
    final captured = await pump(tester);

    await tester.tap(find.text('✏️ 직접 입력'));
    await tester.pump();
    // 입력 필드 노출.
    expect(find.byKey(const ValueKey('emotion-custom-field')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('emotion-custom-field')), '설레는');
    await tester.pump();
    expect(captured[0], isNull);
    expect(captured[1], '설레는');
  });

  testWidgets('직접 입력은 20자로 제한(maxLength)', (tester) async {
    await pump(tester);
    await tester.tap(find.text('✏️ 직접 입력'));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('emotion-custom-field')),
    );
    expect(field.maxLength, 20);
    // 길이 제한 포매터가 걸려 있다.
    expect(
      field.inputFormatters?.whereType<LengthLimitingTextInputFormatter>().first
          .maxLength,
      20,
    );
  });

  testWidgets('프리셋 선택 후 직접 입력 진입 → 프리셋 해제(상호 배타)', (tester) async {
    final captured = await pump(tester);

    await tester.tap(find.text('😊 기쁨'));
    await tester.pump();
    expect(captured[0], 'JOY');

    // 직접 입력 진입 → emotion 해제(null), 이후 label만 유효.
    await tester.tap(find.text('✏️ 직접 입력'));
    await tester.pump();
    expect(captured[0], isNull);
    expect(captured[1], isNull); // 아직 입력 없음
  });

  testWidgets('최근 사용 추천 칩 탭 → 입력 필드에 값 채움', (tester) async {
    final captured = await pump(tester, recent: ['뿌듯한', '지치는']);

    // 직접 입력 모드 진입 후에 최근 칩이 노출된다.
    await tester.tap(find.text('✏️ 직접 입력'));
    await tester.pump();
    expect(find.text('뿌듯한'), findsOneWidget);

    await tester.tap(find.text('뿌듯한'));
    await tester.pump();
    expect(captured[0], isNull);
    expect(captured[1], '뿌듯한');
  });
}
