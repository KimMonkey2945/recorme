// 공통 위젯 스모크 테스트.
// (flutter create가 되살린 기본 카운터 테스트를 대체. 본격적인 화면/플로우 위젯
//  테스트는 Phase 2 T8에서 추가한다.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/shared/widgets/empty_state_view.dart';

void main() {
  testWidgets('EmptyStateView가 아이콘과 메시지를 렌더한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateView(
            icon: Icons.book_outlined,
            message: '아직 작성한 일기가 없어요',
          ),
        ),
      ),
    );

    expect(find.text('아직 작성한 일기가 없어요'), findsOneWidget);
    expect(find.byIcon(Icons.book_outlined), findsOneWidget);
  });
}
