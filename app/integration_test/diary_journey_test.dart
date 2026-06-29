// 기록 기능 E2E(통합) 테스트 — Fake/Stub override 기반.
//
// ## 목표
// 실제 앱 위젯 트리(go_router + Riverpod)를 그대로 구동해, 캘린더→에디터 진입,
// 목록→상세→삭제로 이어지는 핵심 사용자 여정을 결정적으로 검증한다.
//
// ## 리치 에디터(flutter_quill) 도입에 따른 제약
// - 본문은 QuillEditor로 렌더되며, 위젯 테스트에서 에디터에 직접 타이핑하는 것은
//   불안정하다(자체 입력 연결·커서 타이머). 따라서 "본문 작성→저장"은 저장소에
//   미리 시드한 데이터로 대체하고, 에디터는 "열림(툴바/카운터)"까지만 검증한다.
//   실제 타이핑·서식·인라인 이미지·저장 흐름은 수동(브라우저) 검증 대상이다.
//
// ## 외부 의존 우회(결정성)
// - 로그인 가드: authControllerProvider를 항상 authenticated인 Fake로 override.
// - 기록 저장소: diaryRepositoryProvider를 인메모리 _E2EDiaryRepository로 override.
// - 프로필 아바타: myProfileProvider를 더미 User로 override(Dio/Supabase 차단).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:record/app.dart';
import 'package:record/core/error/failure.dart';
import 'package:record/features/auth/presentation/providers/auth_provider.dart';
import 'package:record/features/diary/data/dto/diary_dto.dart';
import 'package:record/features/diary/domain/diary_content.dart';
import 'package:record/features/diary/domain/diary_repository.dart';
import 'package:record/features/diary/presentation/providers/diary_providers.dart';
import 'package:record/features/diary/presentation/widgets/diary_list_tile.dart';
import 'package:record/features/profile/presentation/providers/profile_providers.dart';
import 'package:record/shared/models/cursor_page.dart';
import 'package:record/shared/models/user.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 인증 가드 우회용 Fake 컨트롤러
// ─────────────────────────────────────────────────────────────────────────────

class _FakeAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

// ─────────────────────────────────────────────────────────────────────────────
// 인메모리 E2E 기록 저장소
// ─────────────────────────────────────────────────────────────────────────────

/// 결정적 E2E 전용 기록 저장소.
///
/// - 네트워크 지연 없이 즉시 반환.
/// - upsert 결과는 analysisStatus 'DONE'(상세 PENDING 무한 스피너 방지).
/// - 목록 응답의 content는 평문 미리보기(백엔드 미러링), 단건은 Delta JSON.
class _E2EDiaryRepository implements DiaryRepository {
  final Map<int, Diary> _diaries = {};
  int _nextId = 1;

  String _ym(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 목록 미리보기(평문 content)로 변환.
  Diary _asListItem(Diary d) => Diary(
        id: d.id,
        content: d.contentText ?? plainTextOf(documentFromContent(d.content)),
        writtenDate: d.writtenDate,
        visibility: d.visibility,
        analysisStatus: d.analysisStatus,
      );

  /// 테스트 시드: 특정 날짜에 Delta 본문 기록을 직접 넣는다.
  /// DONE 상태 + 감정 테마/AI 필드까지 채워, 상세 화면의 무드 카드·배경 틴트가
  /// 실제로 렌더링되는 경로를 E2E로 검증할 수 있게 한다.
  void seed(DateTime date, String text) {
    final id = _nextId++;
    _diaries[id] = Diary(
      id: id,
      content: contentJsonFromPlain(text),
      contentText: text,
      writtenDate: DateTime(date.year, date.month, date.day),
      visibility: 'PRIVATE',
      analysisStatus: 'DONE',
      primaryEmotion: 'JOY',
      backgroundColor: '#FFF3D6',
      textColor: '#3A2E12',
      accentColor: '#F5A623',
      moodEmoji: '😊',
      aiTitle: '평온한 하루',
      aiComment: '오늘도 수고 많았어요',
    );
  }

  @override
  Future<DiarySummary> getMonthlySummary(String yearMonth) async {
    // 해당 월 기록을 날짜 오름차순으로 DiarySummaryDay 목록으로 변환한다.
    final days = (_diaries.values
          .where((d) => _ym(d.writtenDate) == yearMonth)
          .toList()
        ..sort((a, b) => _ymd(a.writtenDate).compareTo(_ymd(b.writtenDate))))
        .map((d) => DiarySummaryDay(
              date: _ymd(d.writtenDate),
              analysisStatus: d.analysisStatus,
              primaryEmotion: d.primaryEmotion,
              moodEmoji: d.moodEmoji,
            ))
        .toList();
    return DiarySummary(yearMonth: yearMonth, days: days);
  }

  @override
  Future<Diary?> getByDate(DateTime date) async {
    final key = _ymd(date);
    for (final d in _diaries.values) {
      if (_ymd(d.writtenDate) == key) return d;
    }
    return null;
  }

  @override
  Future<Diary> getById(int id) async {
    final d = _diaries[id];
    if (d == null) {
      throw const Failure('DIARY_NOT_FOUND', '일기를 찾을 수 없습니다.');
    }
    return d;
  }

  @override
  Future<CursorPage<Diary>> getList({int? cursor, int size = 20}) async {
    final sorted = _diaries.values.toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    return CursorPage<Diary>(
      items: sorted.map(_asListItem).toList(),
      nextCursor: null,
      hasNext: false,
    );
  }

  @override
  Future<List<Diary>> getMonthList(String yearMonth) async {
    final sorted = _diaries.values
        .where((d) => _ymd(d.writtenDate).startsWith(yearMonth))
        .toList()
      ..sort((a, b) => b.writtenDate.compareTo(a.writtenDate));
    return sorted.map(_asListItem).toList();
  }

  @override
  Future<Diary> upsert({
    required DateTime date,
    required String content,
    required String contentText,
    bool confirm = false,
  }) async {
    final key = _ymd(date);
    for (final entry in _diaries.entries) {
      if (_ymd(entry.value.writtenDate) == key) {
        final updated = Diary(
          id: entry.key,
          content: content,
          contentText: contentText,
          writtenDate: entry.value.writtenDate,
          visibility: entry.value.visibility,
          // E2E 테스트는 즉시 DONE으로 반환(PENDING 무한 스피너 방지).
          analysisStatus: 'DONE',
        );
        _diaries[entry.key] = updated;
        return updated;
      }
    }
    final id = _nextId++;
    final created = Diary(
      id: id,
      content: content,
      contentText: contentText,
      writtenDate: DateTime(date.year, date.month, date.day),
      visibility: 'PRIVATE',
      analysisStatus: 'DONE',
    );
    _diaries[id] = created;
    return created;
  }

  @override
  Future<void> delete(int id) async {
    _diaries.remove(id);
  }

  @override
  Future<String> uploadImage(Uint8List bytes, String filename) async =>
      '/files/diaries/fake/$filename';
}

// ─────────────────────────────────────────────────────────────────────────────
// 펌프 헬퍼
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _pumpApp(WidgetTester tester, _E2EDiaryRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        diaryRepositoryProvider.overrideWithValue(repo),
        myProfileProvider.overrideWith(
          (ref) async => const User(uuid: 'e2e-user', nickname: '테스터'),
        ),
      ],
      child: const RecordApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _drainSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 시드/표시는 현재 달 기준으로 한다(캘린더·목록이 현재 달을 보여주므로).
  final now = DateTime.now();
  final seedDate = DateTime(now.year, now.month, 15);

  group('일기 E2E 여정', () {
    testWidgets('목록→상세→삭제 + 캘린더 날짜 재작성 허용', (tester) async {
      final repo = _E2EDiaryRepository()..seed(seedDate, '시드 일기 본문');
      await _pumpApp(tester, repo);

      // 캘린더 진입(시드된 날짜에 '기록 있음' dot).
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // ── 목록 탭 → 시드 기록 노출(평문 미리보기) ───────────────────────────
      await tester.tap(find.text('목록'));
      await tester.pumpAndSettle();
      expect(find.byType(DiaryListTile), findsOneWidget);
      expect(find.text('시드 일기 본문'), findsOneWidget);

      // ── 항목 탭 → 상세(읽기전용 에디터 + DONE 무드 카드) ──────────────────
      await tester.tap(find.byType(DiaryListTile));
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsOneWidget);
      // DONE 기록: 무드 카드의 AI 제목·코멘트가 노출된다(상태 배지는 DONE에서 숨김).
      expect(find.text('평온한 하루'), findsOneWidget);
      expect(find.text('오늘도 수고 많았어요'), findsOneWidget);
      // 확정 기록(isDraft=false)은 수정 불가 → 수정 버튼 없음, 삭제만 노출.
      expect(find.widgetWithText(OutlinedButton, '수정'), findsNothing);
      expect(find.text('삭제'), findsOneWidget);

      // ── 삭제(확인 다이얼로그) → 메인 복귀 ────────────────────────────────
      await tester.tap(find.widgetWithText(OutlinedButton, '삭제'));
      await tester.pumpAndSettle();
      expect(find.text('일기 삭제'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      await _drainSnackBars(tester);

      expect(find.byType(FloatingActionButton), findsOneWidget);

      // 같은 날짜(15일) 재탭 → 삭제로 비워져 신규 작성 모드.
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      expect(find.text('일기 쓰기'), findsOneWidget);
    });

    testWidgets('캘린더 날짜 탭 → 리치 에디터 열림(툴바·카운터)', (tester) async {
      final repo = _E2EDiaryRepository();
      await _pumpApp(tester, repo);

      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      expect(find.text('일기 쓰기'), findsOneWidget); // 신규 모드 타이틀
      expect(find.byType(QuillSimpleToolbar), findsOneWidget); // 서식 툴바
      expect(find.byType(QuillEditor), findsOneWidget); // 본문 에디터
      expect(find.text('0 / 500'), findsOneWidget); // 초기 글자수 카운터
    });
  });
}
