// Phase 3 UI 위젯/페이지 테스트(리치 텍스트 에디터 도입 후).
// - 표현 위젯(DiaryListTile / DiaryDetailView / DiaryEditorView / CalendarMonthView)
// - 페이지(목록/상세/에디터): ProviderScope override로 더미 저장소 주입
//
// 비고: 본문은 flutter_quill로 렌더되므로 본문 텍스트는 일반 Text 위젯이 아니다.
// 따라서 상세/에디터 본문은 find.text 대신 QuillEditor 존재로 검증한다.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/diary/data/dto/diary_dto.dart';
import 'package:record/features/diary/domain/diary_content.dart';
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
  Future<List<Diary>> getMonthList(String yearMonth) async => items;

  @override
  Future<Diary> upsert({
    required DateTime date,
    required String content,
    required String contentText,
  }) async =>
      items.first;

  @override
  Future<void> delete(int id) async {}

  @override
  Future<String> uploadImage(Uint8List bytes, String filename) async =>
      '/files/diaries/fake/$filename';
}

/// 목록 미리보기용(평문 content) 일기.
Diary _listDiary({
  int id = 1,
  String content = '오늘은 평온한 하루였다',
  String status = 'DONE',
}) =>
    Diary(
      id: id,
      content: content,
      writtenDate: DateTime(2026, 6, 24),
      visibility: 'PRIVATE',
      analysisStatus: status,
    );

/// 상세/에디터용(Delta JSON content) 일기.
Diary _richDiary({
  int id = 1,
  String text = '오늘은 평온한 하루였다',
  String status = 'DONE',
}) =>
    Diary(
      id: id,
      content: contentJsonFromPlain(text),
      contentText: text,
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

    testWidgets('DiaryDetailView: 읽기전용 에디터·배지 렌더 + 수정/삭제 콜백',
        (tester) async {
      var edited = false;
      var deleted = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
        supportedLocales: FlutterQuillLocalizations.supportedLocales,
        home: Scaffold(
          body: DiaryDetailView(
            dateText: '2026년 6월 24일 (화)',
            content: contentJsonFromPlain('상세 본문입니다'),
            analysisStatus: 'DONE',
            onEdit: () => edited = true,
            onDelete: () => deleted = true,
          ),
        ),
      ));
      await tester.pump();

      // 본문은 QuillEditor로 렌더(일반 Text 아님).
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.text('분석 완료'), findsOneWidget);

      await tester.tap(find.text('수정'));
      await tester.tap(find.text('삭제'));
      expect(edited, true);
      expect(deleted, true);
    });

    testWidgets('DiaryEditorView: canSave에 따라 저장 버튼 활성/비활성 + onSave',
        (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      var saved = false;

      // 단일 행 툴바가 가로로 잘리지 않도록 넓은 화면으로.
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Widget build(bool canSave) => MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            supportedLocales: FlutterQuillLocalizations.supportedLocales,
            home: Scaffold(
              body: DiaryEditorView(
                dateText: '2026년 6월 24일',
                controller: controller,
                plainLength: canSave ? 5 : 0,
                saving: false,
                canSave: canSave,
                onSave: () => saved = true,
                onCancel: () {},
                onPickImage: () {},
              ),
            ),
          );

      // 비활성: 내용 없음.
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsOneWidget);
      final saveBtn = find.widgetWithText(FilledButton, '저장');
      expect(tester.widget<FilledButton>(saveBtn).onPressed, isNull);
      expect(find.text('0 / 500'), findsOneWidget);

      // 활성: 내용 있음 → 탭 시 onSave.
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(saveBtn).onPressed, isNotNull);
      await tester.tap(saveBtn);
      expect(saved, true);
      expect(find.text('5 / 500'), findsOneWidget);
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

    testWidgets('CalendarMonthView: 미래 날짜 셀은 탭이 무효(콜백 미호출)', (tester) async {
      DateTime? tappedDate;
      // 명백히 미래인 달 → 모든 날짜가 비활성.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CalendarMonthView(
            month: DateTime(2999, 1),
            markedDates: const {},
            onDateTap: (d) => tappedDate = d,
          ),
        ),
      ));

      await tester.tap(find.text('15'));
      await tester.pump();
      expect(tappedDate, isNull); // 미래 날짜라 콜백이 호출되지 않아야 한다
    });
  });

  group('페이지 (더미 저장소 주입)', () {
    Widget wrap(Widget child, DiaryRepository repo) => ProviderScope(
          overrides: [diaryRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            supportedLocales: FlutterQuillLocalizations.supportedLocales,
            home: child,
          ),
        );

    testWidgets('DiaryListPage: 주입된 일기 타일을 렌더', (tester) async {
      final repo = _StubRepo([
        _listDiary(id: 2, content: '두 번째 일기'),
        _listDiary(id: 1, content: '첫 번째 일기'),
      ]);
      await tester.pumpWidget(wrap(const DiaryListPage(), repo));
      await tester.pumpAndSettle();

      expect(find.byType(DiaryListTile), findsNWidgets(2));
      expect(find.text('두 번째 일기'), findsOneWidget);
    });

    testWidgets('DiaryDetailPage: 주입된 단건을 읽기전용 에디터로 렌더', (tester) async {
      final repo = _StubRepo([_richDiary(id: 7, text: '상세 화면 본문')]);
      await tester.pumpWidget(wrap(const DiaryDetailPage(diaryId: '7'), repo));
      await tester.pumpAndSettle();

      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.text('수정'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
    });

    testWidgets('DiaryEditorPage: 신규 모드(빈 입력)로 렌더', (tester) async {
      // 단일 행 툴바가 가로로 잘리지 않도록 넓은 화면으로.
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _StubRepo([]); // 해당 날짜 일기 없음 → 신규 모드
      await tester.pumpWidget(
        wrap(const DiaryEditorPage(date: '2026-06-24'), repo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DiaryEditorView), findsOneWidget);
      expect(find.text('일기 쓰기'), findsOneWidget); // AppBar 타이틀(신규)
      expect(find.text('0 / 500'), findsOneWidget); // 초기 글자수 카운터
    });
  });
}
