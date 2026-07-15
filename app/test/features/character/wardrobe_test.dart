// 옷장 화면 테스트.
// - slot 탭 전환·아이템 3상태(보유/미보유/선택) 타일 렌더.
// - 탭 = 로컬 미리보기(스테이지 오버레이 즉시 반영), 저장 = PUT 배치 커밋.
// - 단일 슬롯 재탭 = 해제, ROOM_PROP 다중 진열 카운터.
// - 저장 실패 → 에러 스낵바 + 변경사항 유지 / 취소 → 서버 상태 롤백.
//
// 데이터는 실제 FakeCharacterRepository(V15 시드 미러)를 그대로 쓴다 —
// group↔variant 해석·소유 검증까지 포함해 실제 흐름과 같은 경로를 태운다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/core/error/failure.dart';
import 'package:record/core/theme/app_theme.dart';
import 'package:record/features/character/data/fake_character_repository.dart';
import 'package:record/features/character/domain/item_group.dart';
import 'package:record/features/character/domain/my_character.dart';
import 'package:record/features/character/presentation/providers/character_providers.dart';
import 'package:record/features/character/presentation/wardrobe_page.dart';
import 'package:record/features/character/presentation/widgets/idle_character_view.dart';
import 'package:record/features/character/presentation/widgets/wardrobe_save_bar.dart';
import 'package:record/shared/widgets/loading_view.dart';

/// 저장 실패 경로 검증용 — 착용 커밋만 실패시킨다.
class _FailingReplaceRepository extends FakeCharacterRepository {
  _FailingReplaceRepository() : super(selectedCode: 'MONKEY');

  int replaceCallCount = 0;

  @override
  Future<MyCharacter> replaceEquipment(
      List<EquipmentSelection> equipment) async {
    replaceCallCount++;
    throw const Failure('ITEM_NOT_OWNED', '아직 보유하지 않은 아이템이에요.');
  }
}

/// myCharacterProvider는 인증 상태를 타므로, 테스트에서는 저장소 직결로 override한다.
Widget _wrap(FakeCharacterRepository repo) => ProviderScope(
      overrides: [
        characterRepositoryProvider.overrideWithValue(repo),
        myCharacterProvider.overrideWith(
          (ref) => ref.watch(characterRepositoryProvider).fetchMyCharacter(),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const WardrobePage()),
    );

void main() {
  setUp(() => IdleCharacterView.debugDisableIdleAnimation = true);
  tearDown(() => IdleCharacterView.debugDisableIdleAnimation = false);

  /// 현재 스테이지 미리보기에 배선된 오버레이 경로.
  List<String> overlayPaths(WidgetTester tester) => tester
      .widget<IdleCharacterView>(find.byType(IdleCharacterView))
      .overlayAssetPaths;

  /// 저장 바 표시 여부(AnimatedSlide offset으로 판정).
  bool saveBarVisible(WidgetTester tester) {
    final slide = tester.widget<AnimatedSlide>(
      find.descendant(
        of: find.byType(WardrobeSaveBar),
        matching: find.byType(AnimatedSlide),
      ),
    );
    return slide.offset == Offset.zero;
  }

  /// 기본 테스트 뷰포트(800×600)는 미리보기+그리드를 다 담지 못해 타일 탭이
  /// 빗나간다 → 세로로 넉넉한 화면에서 렌더한다.
  Future<void> pumpWardrobe(
    WidgetTester tester,
    FakeCharacterRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repo));
  }

  group('옷장 렌더', () {
    testWidgets('로딩 → HAT 탭 기본: 보유(파티)·미보유(밀짚, 가격 캡션) 타일', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));

      expect(find.byType(LoadingView), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('파티 모자'), findsOneWidget);
      expect(find.text('밀짚모자'), findsOneWidget);
      // 미보유 코인 아이템은 가격 캡션 + 잠금 아이콘.
      expect(find.text('120코인'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      // 변경 전이라 저장 바는 내려가 있다.
      expect(saveBarVisible(tester), isFalse);
    });

    testWidgets('slot 탭 전환 → 해당 슬롯 아이템만 렌더', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('wardrobe-slot-OUTFIT')));
      await tester.pumpAndSettle();

      expect(find.text('기본 흰 티셔츠'), findsOneWidget);
      expect(find.text('파티 모자'), findsNothing);
    });

    testWidgets('빈 슬롯(PROP) → 빈 상태 안내', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('wardrobe-slot-PROP')));
      await tester.pumpAndSettle();

      expect(find.text('이 칸에 넣을 아이템이 아직 없어요.'), findsOneWidget);
    });
  });

  group('로컬 미리보기(탭 = 미커밋)', () {
    testWidgets('보유 아이템 탭 → 스테이지 오버레이 즉시 반영 + 저장 바 등장', (tester) async {
      final repo = FakeCharacterRepository(selectedCode: 'MONKEY');
      await pumpWardrobe(tester, repo);
      await tester.pumpAndSettle();

      expect(overlayPaths(tester), isEmpty);

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_PARTY')));
      await tester.pumpAndSettle();

      // 미리보기에 원숭이용 variant가 얹혔다.
      expect(overlayPaths(tester), const ['assets/items/hat_party_monkey.png']);
      expect(saveBarVisible(tester), isTrue);
      expect(find.text('변경사항이 있어요'), findsOneWidget);
    });

    testWidgets('같은 아이템 재탭 → 해제(저장 바 다시 내려감)', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_PARTY')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_PARTY')));
      await tester.pumpAndSettle();

      expect(overlayPaths(tester), isEmpty);
      expect(saveBarVisible(tester), isFalse);
    });

    testWidgets('미보유 아이템은 탭해도 반응 없음(타일 비활성)', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_STRAW')));
      await tester.pumpAndSettle();

      expect(overlayPaths(tester), isEmpty);
      expect(saveBarVisible(tester), isFalse);
    });

    testWidgets('ROOM_PROP 탭 → 다중 진열 카운터 갱신', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('wardrobe-slot-ROOM_PROP')));
      await tester.pumpAndSettle();
      expect(find.text('0 / 5개 진열 중'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('item-tile-ROOM_PROP_PLANT')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 5개 진열 중'), findsOneWidget);
    });

    testWidgets('취소 → 서버 상태로 롤백', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_PARTY')));
      await tester.pumpAndSettle();
      expect(overlayPaths(tester), isNotEmpty);

      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect(overlayPaths(tester), isEmpty);
      expect(saveBarVisible(tester), isFalse);
    });
  });

  group('저장(배치 커밋)', () {
    testWidgets('저장 → 착용 반영 + 성공 스낵바 + 저장 바 내려감', (tester) async {
      final repo = FakeCharacterRepository(selectedCode: 'MONKEY');
      await pumpWardrobe(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_PARTY')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wardrobe-save')));
      await tester.pumpAndSettle();

      expect(find.text('옷장을 저장했어요.'), findsOneWidget);
      // 서버(Fake) 상태에 커밋됐다 — 내 캐릭터 응답에 착용이 실린다.
      // (FakeAsync 존에서는 Fake의 지연 타이머가 시간을 펌프해야 발화한다.)
      final myFuture = repo.fetchMyCharacter();
      await tester.pump(const Duration(milliseconds: 400));
      final my = await myFuture;
      expect(my.equipment, hasLength(1));
      expect(my.equipment.first.groupCode, 'HAT_PARTY');
      expect(my.equipment.first.slot, 'HAT');
      // 커밋 후에는 변경사항이 없다.
      expect(saveBarVisible(tester), isFalse);

      // 스낵바 타이머 정리.
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('저장 실패 → 에러 스낵바 + 변경사항(저장 바) 유지', (tester) async {
      final repo = _FailingReplaceRepository();
      await pumpWardrobe(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_PARTY')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wardrobe-save')));
      await tester.pumpAndSettle();

      expect(repo.replaceCallCount, 1);
      expect(find.text('아직 보유하지 않은 아이템이에요.'), findsOneWidget);
      // 로컬 변경은 날아가지 않는다 — 다시 저장을 시도할 수 있어야 한다.
      expect(saveBarVisible(tester), isTrue);
      expect(overlayPaths(tester), const ['assets/items/hat_party_monkey.png']);

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });
}
