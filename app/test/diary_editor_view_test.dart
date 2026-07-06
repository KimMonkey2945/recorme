// DiaryEditorView 위젯 테스트(리치 텍스트 에디터 도입 후).
//
// 본문은 flutter_quill로 렌더되고, 글자수 제한·이미지 삽입·저장 로직은 상위
// 페이지(DiaryEditorPage)가 담당한다. 이 위젯은 컨트롤러/콜백을 받아 표시만 하므로,
// 여기서는 표시(툴바·에디터·카운터)와 콜백 배선만 검증한다.
//
// 변경 이력:
// - '등록'/'오늘을 기억하기' 버튼 분리에 따라 onSave → onRegister/onRemember로 수정.

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/diary/presentation/widgets/diary_editor_view.dart';

/// DiaryEditorView를 MaterialApp으로 감싸 펌프하는 헬퍼.
Future<void> _pump(
  WidgetTester tester, {
  required QuillController controller,
  int plainLength = 0,
  bool saving = false,
  VoidCallback? onRegister,
  VoidCallback? onRemember,
  VoidCallback? onPickImage,
}) async {
  // 단일 행 툴바가 가로로 잘리지 않도록 넓은 화면으로 펌프(이미지 버튼이 화면 안에 들어옴).
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
    supportedLocales: FlutterQuillLocalizations.supportedLocales,
    home: Scaffold(
      body: DiaryEditorView(
        dateText: '2026년 6월 24일',
        controller: controller,
        // 길이는 리스너블로 주입(실제 페이지의 ValueNotifier 흐름과 동일).
        plainLength: ValueNotifier<int>(plainLength),
        saving: saving,
        visibility: 'PRIVATE',
        onVisibilityChanged: (_) {},
        onRegister: onRegister ?? () {},
        onRemember: onRemember ?? () {},
        onCancel: () {},
        onPickImage: onPickImage ?? () {},
      ),
    ),
  ));
  // Quill가 예약하는 1회성 타이머를 비우기 위해 settle.
  await tester.pumpAndSettle();
}

void main() {
  group('DiaryEditorView', () {
    testWidgets('툴바·에디터·카운터 렌더', (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);

      await _pump(tester, controller: controller, plainLength: 0);

      expect(find.byType(QuillSimpleToolbar), findsOneWidget);
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.text('0 / 500'), findsOneWidget);
    });

    testWidgets('plainLength가 카운터에 반영', (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);

      await _pump(tester, controller: controller, plainLength: 123);
      expect(find.text('123 / 500'), findsOneWidget);
    });

    testWidgets('내용 없으면 기억하기 버튼 비활성, 있으면 활성 + onRemember 호출',
        (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      var remembered = false;

      // 비활성: 내용 없음(plainLength=0 → canSave 파생값 false).
      await _pump(tester, controller: controller, plainLength: 0);
      final rememberBtn = find.widgetWithText(FilledButton, '오늘을 기억하기');
      expect(tester.widget<FilledButton>(rememberBtn).onPressed, isNull);

      // 활성: 내용 있음 → 탭 시 onRemember.
      await _pump(
        tester,
        controller: controller,
        plainLength: 5,
        onRemember: () => remembered = true,
      );
      expect(tester.widget<FilledButton>(rememberBtn).onPressed, isNotNull);
      await tester.tap(rememberBtn);
      expect(remembered, true);
    });

    testWidgets('내용 없으면 등록 버튼 비활성, 있으면 활성 + onRegister 호출',
        (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      var registered = false;

      // 비활성: 내용 없음(plainLength=0 → canSave 파생값 false).
      await _pump(tester, controller: controller, plainLength: 0);
      final registerBtn = find.widgetWithText(OutlinedButton, '등록');
      expect(tester.widget<OutlinedButton>(registerBtn).onPressed, isNull);

      // 활성: 내용 있음 → 탭 시 onRegister.
      await _pump(
        tester,
        controller: controller,
        plainLength: 5,
        onRegister: () => registered = true,
      );
      expect(tester.widget<OutlinedButton>(registerBtn).onPressed, isNotNull);
      await tester.tap(registerBtn);
      expect(registered, true);
    });

    testWidgets('사진 삽입 버튼 탭 시 onPickImage 호출', (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      var picked = false;

      await _pump(
        tester,
        controller: controller,
        onPickImage: () => picked = true,
      );

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pump();
      expect(picked, true);
    });
  });
}
