// 옷장 화면 테스트.
// - slot 탭 전환·아이템 타일 렌더(전부 COIN·미보유 → 잠금/가격 캡션).
// - 미보유 탭 = 코인 해금 안내 시트, 보유 탭 = 로컬 미리보기(스테이지 오버레이).
// - 저장 = PUT 배치 커밋, 저장 실패 → 에러 스낵바 + 변경사항 유지 / 취소 → 롤백.
//
// V21 카탈로그(5종 전부 COIN·미보유)라, 착용 흐름은 FakeCharacterRepository(ownedGroups: {...})로
// 소유를 주입해 검증한다(구매 기능 전까지 프로덕션 기본은 전부 잠금).

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

/// 착용 커밋만 실패시킨다(모자는 보유로 둬 저장까지 도달하게 함).
class _FailingReplaceRepository extends FakeCharacterRepository {
  _FailingReplaceRepository()
      : super(selectedCode: 'MONKEY', ownedGroups: const {'HAT_CAP_BLACK'});

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
    testWidgets('로딩 → HAT 탭 기본: 검은 캡모자(미보유·15코인·잠금)', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));

      expect(find.byType(LoadingView), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')),
          findsOneWidget);
      expect(find.text('누구나 소화할 수 있는 검은색 캡모자'), findsOneWidget);
      // 전부 COIN·미보유라 가격 캡션 + 잠금 아이콘(HAT 슬롯엔 1종뿐).
      expect(find.text('15코인'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      // 변경 전이라 저장 바는 내려가 있다.
      expect(saveBarVisible(tester), isFalse);
    });

    testWidgets('slot 탭 전환 → 해당 슬롯 아이템만 렌더', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('wardrobe-slot-OUTFIT')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('item-tile-OUTFIT_LOVE_HOOD')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')), findsNothing);
      expect(find.text('50코인'), findsOneWidget);
    });
  });

  group('잠금(미보유) 아이템', () {
    testWidgets('미보유 탭 → 코인 해금 안내 시트(착용 안 됨)', (tester) async {
      await pumpWardrobe(tester, FakeCharacterRepository(selectedCode: 'MONKEY'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();

      // 코인 구매 안내 바텀시트(가격 헤더 + 구매 버튼).
      expect(find.text('15코인으로 구매'), findsOneWidget);
      expect(find.text('15코인으로 구매하기'), findsOneWidget);
      // 잠금이라 착용(오버레이/저장 바)은 발생하지 않는다.
      expect(overlayPaths(tester), isEmpty);
      expect(saveBarVisible(tester), isFalse);
    });
  });

  group('로컬 미리보기(보유 아이템 · 탭 = 미커밋)', () {
    testWidgets('보유 아이템 탭 → 스테이지 오버레이 즉시 반영 + 저장 바 등장', (tester) async {
      final repo = FakeCharacterRepository(
          selectedCode: 'MONKEY', ownedGroups: const {'HAT_CAP_BLACK'});
      await pumpWardrobe(tester, repo);
      await tester.pumpAndSettle();

      expect(overlayPaths(tester), isEmpty);

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();

      // 미리보기에 원숭이용 variant가 얹혔다.
      expect(overlayPaths(tester),
          const ['assets/items/hat_cap_black_monkey.png']);
      expect(saveBarVisible(tester), isTrue);
      expect(find.text('변경사항이 있어요'), findsOneWidget);
    });

    testWidgets('같은 아이템 재탭 → 해제(저장 바 다시 내려감)', (tester) async {
      await pumpWardrobe(
          tester,
          FakeCharacterRepository(
              selectedCode: 'MONKEY', ownedGroups: const {'HAT_CAP_BLACK'}));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();

      expect(overlayPaths(tester), isEmpty);
      expect(saveBarVisible(tester), isFalse);
    });

    testWidgets('취소 → 서버 상태로 롤백', (tester) async {
      await pumpWardrobe(
          tester,
          FakeCharacterRepository(
              selectedCode: 'MONKEY', ownedGroups: const {'HAT_CAP_BLACK'}));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();
      expect(overlayPaths(tester), isNotEmpty);

      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect(overlayPaths(tester), isEmpty);
      expect(saveBarVisible(tester), isFalse);
    });
  });

  group('구매(코인 소비)', () {
    testWidgets('잠금 아이템 구매 → 성공 스낵바 + 시트 닫힘', (tester) async {
      // 코인 100 보유, 아무것도 미보유.
      await pumpWardrobe(tester,
          FakeCharacterRepository(selectedCode: 'MONKEY', coinBalance: 100));
      await tester.pumpAndSettle();

      // 잠긴 모자 탭 → 잠금 시트 → 구매 버튼.
      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15코인으로 구매하기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('구매했어요'), findsOneWidget);
      // 시트가 닫혔다(구매 안내 문구가 사라짐).
      expect(find.text('15코인으로 구매'), findsNothing);

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('코인 부족 → 에러 스낵바 + 시트 유지', (tester) async {
      // 코인 5(가격 15 미만).
      await pumpWardrobe(tester,
          FakeCharacterRepository(selectedCode: 'MONKEY', coinBalance: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15코인으로 구매하기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('코인이 부족'), findsOneWidget);
      // 시트는 그대로(재시도 가능).
      expect(find.text('15코인으로 구매'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });

  group('저장(배치 커밋)', () {
    testWidgets('저장 → 착용 반영 + 성공 스낵바 + 저장 바 내려감', (tester) async {
      final repo = FakeCharacterRepository(
          selectedCode: 'MONKEY', ownedGroups: const {'HAT_CAP_BLACK'});
      await pumpWardrobe(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wardrobe-save')));
      await tester.pumpAndSettle();

      expect(find.text('옷장을 저장했어요.'), findsOneWidget);
      // 서버(Fake) 상태에 커밋됐다 — 내 캐릭터 응답에 착용이 실린다.
      final myFuture = repo.fetchMyCharacter();
      await tester.pump(const Duration(milliseconds: 400));
      final my = await myFuture;
      expect(my.equipment, hasLength(1));
      expect(my.equipment.first.groupCode, 'HAT_CAP_BLACK');
      expect(my.equipment.first.slot, 'HAT');
      expect(saveBarVisible(tester), isFalse);

      // 스낵바 타이머 정리.
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('저장 실패 → 에러 스낵바 + 변경사항(저장 바) 유지', (tester) async {
      final repo = _FailingReplaceRepository();
      await pumpWardrobe(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('item-tile-HAT_CAP_BLACK')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wardrobe-save')));
      await tester.pumpAndSettle();

      expect(repo.replaceCallCount, 1);
      expect(find.text('아직 보유하지 않은 아이템이에요.'), findsOneWidget);
      // 로컬 변경은 날아가지 않는다 — 다시 저장을 시도할 수 있어야 한다.
      expect(saveBarVisible(tester), isTrue);
      expect(overlayPaths(tester),
          const ['assets/items/hat_cap_black_monkey.png']);

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });
}
