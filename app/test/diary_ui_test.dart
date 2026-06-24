// Phase 2 UI 위젯/페이지 테스트.
// - 표현 위젯(DiaryListTile / DiaryDetailView / DiaryEditorView / CalendarMonthView)
// - 페이지(목록/상세/에디터): ProviderScope override로 더미 저장소 주입

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/diary/data/dto/diary_dto.dart';
import 'package:record/features/diary/domain/diary_repository.dart';
import 'package:record/features/diary/presentation/diary_detail_page.dart';
import 'package:record/features/diary/presentation/diary_editor_page.dart';
import 'package:record/features/diary/presentation/diary_list_page.dart';
import 'package:record/features/diary/presentation/providers/diary_providers.dart';
import 'package:record/features/diary/presentation/widgets/calendar_month_view.dart';
import 'package:record/features/diary/presentation/widgets/diary_detail_view.dart';
import 'package:record/features/diary/presentation/widgets/diary_editor_view.dart';
import 'package:record/features/diary/presentation/widgets/diary_list_tile.dart';
import 'package:record/shared/models/cursor_page.dart';

/// 테스트용 결정적 더미 저장소.
class _StubRepo implements DiaryRepository {
  _StubRepo(this.items);
  final List<Diary> items;

  Diary? _byDate(DateTime d) {
    for (final it in items) {
      if (it.writtenDate.year == d.year &&
          it.writtenDate.month == d.month &&
          it.writtenDate.day == d.day) {
        return it;
      }
    }
    return null;
  }

  @override
  Future<DiarySummary> getMonthlySummary(String yearMonth) async =>
      DiarySummary(yearMonth: yearMonth, dates: const []);

  @override
  Future<Diary?> getByDate(DateTime date) async => _byDate(date);

  @override
  Future<Diary> getById(int id) async => items.firstWhere((e) => e.id == id);

  @override
  Future<CursorPage<Diary>> getList({int? cursor, int size = 20}) async =>
      CursorPage(items: items, nextCursor: null, hasNext: false);

  @override
  Future<Diary> upsert({required DateTime date, required String content}) async =>
      items.first;

  @override
  Future<void> delete(int id) async {}
}

Diary _diary({int id = 1, String content = '오늘은 평온한 하루였다', String status = 'DONE'}) =>
    Diary(
      id: id,
      content: content,
      writtenDate: DateTime(2026, 6, 24),
      visibility: 'PRIVATE',
      analysisStatus: status,
    );

void main() {
  group('표현 위젯', () {
    testWidgets('DiaryListTile: 날짜·미리보기 렌더 + 탭 콜백', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiaryListTile(
            dateText: '6월 24일 (화)',
            preview: '미리보기 내용',
            onTap: () => tapped = true,
          ),
        ),
      ));

      expect(find.text('6월 24일 (화)'), findsOneWidget);
      expect(find.text('미리보기 내용'), findsOneWidget);

      await tester.tap(find.byType(DiaryListTile));
      expect(tapped, true);
    });

    testWidgets('DiaryDetailView: 내용·배지 렌더 + 수정/삭제 콜백', (tester) async {
      var edited = false;
      var deleted = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiaryDetailView(
            dateText: '2026년 6월 24일 (화)',
            content: '상세 본문입니다',
            analysisStatus: 'DONE',
            onEdit: () => edited = true,
            onDelete: () => deleted = true,
          ),
        ),
      ));

      expect(find.text('상세 본문입니다'), findsOneWidget);
      expect(find.text('분석 완료'), findsOneWidget);

      await tester.tap(find.text('수정'));
      await tester.tap(find.text('삭제'));
      expect(edited, true);
      expect(deleted, true);
    });

    testWidgets('DiaryEditorView: 빈 내용이면 저장 비활성, 입력 후 onSave 전달',
        (tester) async {
      String? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiaryEditorView(
            dateText: '2026년 6월 24일',
            saving: false,
            onSave: (c) => saved = c,
            onCancel: () {},
          ),
        ),
      ));

      final saveBtn = find.widgetWithText(FilledButton, '저장');
      expect(tester.widget<FilledButton>(saveBtn).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '오늘의 기록');
      await tester.pump();
      expect(tester.widget<FilledButton>(saveBtn).onPressed, isNotNull);

      await tester.tap(saveBtn);
      expect(saved, '오늘의 기록');
    });

    testWidgets('CalendarMonthView: 월 타이틀 렌더 + 날짜 탭 콜백', (tester) async {
      DateTime? tappedDate;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CalendarMonthView(
            month: DateTime(2026, 6),
            markedDates: {DateTime(2026, 6, 10)},
            onDateTap: (d) => tappedDate = d,
          ),
        ),
      ));

      expect(find.text('2026년 6월'), findsOneWidget);
      await tester.tap(find.text('10'));
      expect(tappedDate, isNotNull);
      expect(tappedDate!.day, 10);
    });
  });

  group('페이지 (더미 저장소 주입)', () {
    Widget wrap(Widget child, DiaryRepository repo) => ProviderScope(
          overrides: [diaryRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: child),
        );

    testWidgets('DiaryListPage: 주입된 일기 타일을 렌더', (tester) async {
      final repo = _StubRepo([
        _diary(id: 2, content: '두 번째 일기'),
        _diary(id: 1, content: '첫 번째 일기'),
      ]);
      await tester.pumpWidget(wrap(const DiaryListPage(), repo));
      await tester.pumpAndSettle();

      expect(find.byType(DiaryListTile), findsNWidgets(2));
      expect(find.text('두 번째 일기'), findsOneWidget);
    });

    testWidgets('DiaryDetailPage: 주입된 단건 내용을 렌더', (tester) async {
      final repo = _StubRepo([_diary(id: 7, content: '상세 화면 본문')]);
      await tester.pumpWidget(wrap(const DiaryDetailPage(diaryId: '7'), repo));
      await tester.pumpAndSettle();

      expect(find.text('상세 화면 본문'), findsOneWidget);
      expect(find.text('수정'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
    });

    testWidgets('DiaryEditorPage: 신규 모드(빈 입력)로 렌더', (tester) async {
      final repo = _StubRepo([]); // 해당 날짜 일기 없음 → 신규 모드
      await tester.pumpWidget(
        wrap(const DiaryEditorPage(date: '2026-06-24'), repo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DiaryEditorView), findsOneWidget);
      expect(find.text('일기 쓰기'), findsOneWidget); // AppBar 타이틀(신규)
    });
  });
}
