// 월간 회고(F032 — 락인) 페이지 테스트.
// - 기록 수·연속일·완주·획득 코인 요약 렌더.
// - 감정 분포 렌더(프리셋 + 커스텀 라벨 혼재).
// - 획득 아이템 렌더.
// - 빈 달(기록 0건) → 빈 상태 UI.
// - 월 이동(이전) 동작 + 미래 달(다음) 차단.
//
// characterRepositoryProvider를 stub으로 override하고, retrospectProvider(family)가 이를 통해 조회한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/core/theme/app_theme.dart';
import 'package:record/features/character/data/fake_character_repository.dart';
import 'package:record/features/character/domain/retrospect.dart';
import 'package:record/features/character/presentation/providers/character_providers.dart';
import 'package:record/features/character/presentation/retrospect_page.dart';

/// getRetrospect만 지정 함수로 돌려주는 stub(지연 없음 — pumpAndSettle 결정적).
class _StubRetrospectRepository extends FakeCharacterRepository {
  _StubRetrospectRepository(this._build);

  final Retrospect Function(String yearMonth) _build;

  @override
  Future<Retrospect> getRetrospect(String yearMonth) async => _build(yearMonth);
}

Retrospect _rich(String ym) => Retrospect(
      yearMonth: ym,
      confirmedCount: 12,
      consecutiveDaysMax: 5,
      resolutionSuccessCount: 2,
      coinEarned: 210,
      emotions: const [
        EmotionStat(code: 'JOY', labelKo: '기쁨', count: 7),
        EmotionStat(label: '설레는', count: 3), // 직접 입력(커스텀) 라벨
      ],
      unlockedItems: const [
        UnlockedItem(
          groupCode: 'HAT_CAP_BLACK',
          nameKo: '검은색 캡모자',
          imageUrl: 'assets/items/hat_cap_black_monkey.png',
        ),
      ],
    );

Retrospect _empty(String ym) => Retrospect(
      yearMonth: ym,
      confirmedCount: 0,
      consecutiveDaysMax: 0,
      resolutionSuccessCount: 0,
      coinEarned: 0,
      emotions: const [],
      unlockedItems: const [],
    );

Widget _wrap(FakeCharacterRepository repo) => ProviderScope(
      overrides: [characterRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: const RetrospectPage()),
    );

void main() {
  Future<void> pumpPage(WidgetTester tester, FakeCharacterRepository repo) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
  }

  testWidgets('요약 지표·감정 분포(프리셋+커스텀)·획득 아이템 렌더', (tester) async {
    await pumpPage(tester, _StubRetrospectRepository(_rich));

    // 요약 지표 값
    expect(find.text('12'), findsOneWidget); // 기록 수
    expect(find.text('5'), findsOneWidget); // 최장 연속
    expect(find.text('2'), findsOneWidget); // 작심삼일 완주
    expect(find.text('210'), findsOneWidget); // 획득 코인

    // 감정 분포 — 프리셋(기쁨) + 커스텀(설레는)이 함께
    expect(find.text('감정 분포'), findsOneWidget);
    expect(find.text('기쁨'), findsOneWidget);
    expect(find.text('설레는'), findsOneWidget);
    expect(find.text('7'), findsOneWidget); // 기쁨 개수
    expect(find.text('3'), findsOneWidget); // 설레는 개수

    // 획득 아이템
    expect(find.text('이번 달 획득한 아이템'), findsOneWidget);
    expect(find.text('검은색 캡모자'), findsOneWidget);
  });

  testWidgets('빈 달(기록 0건) → 빈 상태 UI', (tester) async {
    await pumpPage(tester, _StubRetrospectRepository(_empty));

    expect(find.text('이번 달 기록이 아직 없어요'), findsOneWidget);
    // 요약 지표·감정 섹션은 렌더하지 않는다.
    expect(find.text('감정 분포'), findsNothing);
  });

  testWidgets('초기엔 이번 달·다음 달 차단(미래), 이전 달로 이동 가능', (tester) async {
    await pumpPage(tester, _StubRetrospectRepository(_rich));

    final now = DateTime.now();
    // 초기 라벨 = 이번 달
    expect(find.text('${now.year}년 ${now.month}월'), findsOneWidget);

    // 다음 달 버튼은 비활성(미래 차단).
    final nextBtn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(nextBtn.onPressed, isNull);

    // 이전 달로 이동.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    final prev = DateTime(now.year, now.month - 1);
    expect(find.text('${prev.year}년 ${prev.month}월'), findsOneWidget);

    // 이전 달로 오면 다음 달 버튼이 활성화된다(더 이상 이번 달이 아님).
    final nextBtn2 = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(nextBtn2.onPressed, isNotNull);
  });
}
