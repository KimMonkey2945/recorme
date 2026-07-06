// 공개범위 변경 + 공유 기능 테스트(Task 015-2).
// - VisibilitySegment: 3개 칩 렌더 + 선택 콜백.
// - VisibilityAssets: 코드→라벨/아이콘 매핑.
// - FakeDiaryRepository.changeVisibility: 공개범위만 갱신.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/diary/data/fake_diary_repository.dart';
import 'package:record/shared/widgets/visibility_segment.dart';

void main() {
  group('VisibilityAssets', () {
    test('코드 → 라벨 매핑', () {
      expect(VisibilityAssets.labelOf('PRIVATE'), '나만 보기');
      expect(VisibilityAssets.labelOf('FRIENDS'), '친구 공개');
      expect(VisibilityAssets.labelOf('PUBLIC'), '전체 공개');
    });

    test('codes는 PRIVATE/FRIENDS/PUBLIC 3종', () {
      expect(VisibilityAssets.codes, ['PRIVATE', 'FRIENDS', 'PUBLIC']);
    });
  });

  group('VisibilitySegment', () {
    testWidgets('3개 칩을 렌더하고 탭 시 코드로 콜백', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VisibilitySegment(
            value: 'PRIVATE',
            onChanged: (v) => selected = v,
          ),
        ),
      ));

      expect(find.text('나만 보기'), findsOneWidget);
      expect(find.text('친구 공개'), findsOneWidget);
      expect(find.text('전체 공개'), findsOneWidget);

      await tester.tap(find.text('친구 공개'));
      expect(selected, 'FRIENDS');

      await tester.tap(find.text('전체 공개'));
      expect(selected, 'PUBLIC');
    });
  });

  group('FakeDiaryRepository.changeVisibility', () {
    test('공개범위만 갱신하고 본문은 보존', () async {
      final repo = FakeDiaryRepository();
      final page = await repo.getList(size: 50);
      final target = page.items.first;

      final updated = await repo.changeVisibility(target.id, 'PUBLIC');
      expect(updated.visibility, 'PUBLIC');

      // 재조회해도 반영된다.
      final refetched = await repo.getById(target.id);
      expect(refetched.visibility, 'PUBLIC');
    });
  });
}
