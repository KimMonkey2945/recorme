// DiaryEditorView 위젯 테스트(리치 텍스트 에디터 도입 후).
//
// 본문은 flutter_quill로 렌더되고, 글자수 제한·이미지 삽입·저장 로직은 상위
// 페이지(DiaryEditorPage)가 담당한다. 이 위젯은 컨트롤러/콜백을 받아 표시만 하므로,
// 여기서는 표시(툴바·에디터·카운터)와 콜백 배선만 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/diary/presentation/widgets/diary_editor_view.dart';

/// DiaryEditorView를 MaterialApp으로 감싸 펌프하는 헬퍼.
Future<void> _pump(
  WidgetTester tester, {
  required QuillController controller,
  int plainLength = 0,
  bool canSave = false,
  bool saving = false,
  VoidCallback? onSave,
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
        plainLength: plainLength,
        saving: saving,
        canSave: canSave,
        onSave: onSave ?? () {},
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

    testWidgets('canSave=false면 저장 비활성, true면 활성 + onSave 호출', (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      var saved = false;

      await _pump(tester, controller: controller, canSave: false);
      final saveBtn = find.widgetWithText(FilledButton, '저장');
      expect(tester.widget<FilledButton>(saveBtn).onPressed, isNull);

      await _pump(
        tester,
        controller: controller,
        plainLength: 5,
        canSave: true,
        onSave: () => saved = true,
      );
      expect(tester.widget<FilledButton>(saveBtn).onPressed, isNotNull);
      await tester.tap(saveBtn);
      expect(saved, true);
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
