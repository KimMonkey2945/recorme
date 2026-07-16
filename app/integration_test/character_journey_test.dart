// 캐릭터 기능 E2E(통합) 테스트 — Fake/Stub override 기반(Task 032).
//
// ## 목표
// 실제 앱 위젯 트리(go_router + Riverpod)를 그대로 구동해 캐릭터 중심 여정을 관통 검증한다:
// 가입(인증 우회) → 캐릭터 선택(온보딩) → 홈 반영(출석 코인) → 옷장 진입 → 이달의 기록(회고) 진입,
// 그리고 **확정 직후 리액션 오버레이 즉시 등장**(대사·코인) → 닫기(ack)까지.
//
// ## 결정성 우회(diary_journey_test와 동일 철학)
// - 리치 에디터(flutter_quill) 타이핑은 위젯 테스트에서 불안정하므로 "본문 작성→확정"은
//   저장소에 미리 시드한 확정 기록 + DiaryDetailPage(showReaction:true) 직접 구동으로 대체한다.
//   실제 타이핑·확정 흐름은 수동(실기기) 검증 대상이다.
// - 구매→착용→홈 반영의 옷장 UI 조작은 wardrobe_test가 커버하므로, 여기서는 저장소 레벨로 관통 확인한다.
// - 외부 의존(로그인·Dio·Supabase)은 provider override로 차단한다.
//
// ⚠️ 이 파일은 device/emulator 에서 `flutter test integration_test -d <device>` 로 실행한다
//    (integration_test 바인딩은 실기기/에뮬레이터가 필요 — 데스크톱 프로젝트 미구성 환경에서는 실행 불가).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:record/app.dart';
import 'package:record/core/theme/app_theme.dart';
import 'package:record/features/auth/presentation/providers/auth_provider.dart';
import 'package:record/features/character/data/fake_character_repository.dart';
import 'package:record/features/character/domain/item_group.dart';
import 'package:record/features/character/presentation/providers/character_providers.dart';
import 'package:record/features/character/presentation/widgets/idle_character_view.dart';
import 'package:record/features/diary/data/dto/diary_dto.dart';
import 'package:record/features/diary/domain/diary_content.dart';
import 'package:record/features/diary/presentation/diary_detail_page.dart';
import 'package:record/features/diary/presentation/providers/diary_providers.dart';
import 'package:record/features/profile/presentation/providers/profile_providers.dart';
import 'package:record/shared/models/user.dart';

/// 인증 가드 우회 — 항상 authenticated.
class _FakeAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

/// 확정 기록 시드(리액션 오버레이 진입용). analysisStatus=DONE 이라 상세가 즉시 렌더된다.
Diary _confirmedDiary(int id) => Diary(
      id: id,
      content: contentJsonFromPlain('오늘 하루를 기록했다'),
      contentText: '오늘 하루를 기록했다',
      writtenDate: DateTime(2026, 7, 16),
      visibility: 'PRIVATE',
      analysisStatus: 'DONE',
      primaryEmotion: 'JOY',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // CharacterStage(IdleCharacterView)의 무한 idle 애니메이션이 pumpAndSettle 을 막지 않게 정지.
  setUp(() => IdleCharacterView.debugDisableIdleAnimation = true);
  tearDown(() => IdleCharacterView.debugDisableIdleAnimation = false);

  group('캐릭터 E2E 여정', () {
    testWidgets('가입 → 온보딩(캐릭터 선택) → 홈 → 옷장 → 이달의 기록(회고) 관통', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 미선택(character==null) + 코인 100 → 라우터 가드가 온보딩으로 보낸다.
      final charRepo =
          FakeCharacterRepository(selectedCode: null, coinBalance: 100);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            characterRepositoryProvider.overrideWithValue(charRepo),
            myProfileProvider.overrideWith(
              (ref) async => const User(uuid: 'e2e-user', nickname: '테스터'),
            ),
          ],
          child: const RecordApp(),
        ),
      );
      await tester.pumpAndSettle();

      // ── 온보딩: 캐릭터 2종 카드 + "선택" ──────────────────────────────────
      expect(find.text('선택'), findsOneWidget);
      await tester.tap(find.text('선택'));
      // 선택 제출(300ms) + 내 캐릭터 재조회 + 홈 출석(코인 +10) 스낵바(4s) 정착.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // ── 캐릭터 홈: 이름·주 액션·회고 진입 버튼 ────────────────────────────
      expect(find.text('원숭이'), findsOneWidget);
      expect(find.text('옷장'), findsOneWidget);
      expect(find.text('이달의 기록'), findsOneWidget);

      // ── 이달의 기록(회고) 진입 — 확정 기록이 없으니 빈 상태 ────────────────
      await tester.tap(find.text('이달의 기록'));
      await tester.pumpAndSettle();
      expect(find.text('이번 달 기록이 아직 없어요'), findsOneWidget);
    });

    testWidgets('확정 직후 리액션 오버레이 즉시 등장(대사·코인) → 닫기(ack)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final charRepo = FakeCharacterRepository(selectedCode: 'MONKEY');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            characterRepositoryProvider.overrideWithValue(charRepo),
            // myCharacterProvider 는 인증을 타므로 저장소 직결로 override(character_home_test 패턴).
            myCharacterProvider.overrideWith(
              (ref) =>
                  ref.watch(characterRepositoryProvider).fetchMyCharacter(),
            ),
            // 확정 기록 단건을 시드(에디터 타이핑 우회).
            diaryByIdProvider(1).overrideWith((ref) async => _confirmedDiary(1)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            // 확정 직후 진입 신호(reaction=1)를 켜 오버레이가 뜨게 한다.
            home: const DiaryDetailPage(diaryId: '1', showReaction: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ── 리액션 오버레이: 대기·스피너 없이 즉시 대사 1줄 + 코인 획득 카드 ───────
      expect(find.textContaining('천천히 해도'), findsOneWidget); // 원숭이 CONFIRM 대사
      expect(find.text('코인 +10'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);

      // ── 닫기 → ack(배지 감소) → 오버레이 사라짐 ───────────────────────────
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('코인 +10'), findsNothing);
    });

    test('같은 기록 재조회 시 코인 중복 적립 없음(Task 028 멱등 게이트의 앱 레벨 확인)', () async {
      final repo = FakeCharacterRepository(selectedCode: 'MONKEY');

      final first = await repo.getReaction(1);
      final second = await repo.getReaction(1); // 재진입(재전달) — 같은 이벤트

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second!.id, first!.id); // 같은 리액션(새 이벤트가 아니다)

      // 코인은 최초 1회(+10)만 적립돼야 한다 — 재조회로 20이 되면 안 된다.
      final my = await repo.fetchMyCharacter();
      expect(my.coinBalance, 10);
    });

    test('구매 → 착용 → 내 캐릭터 반영(옷장 루프의 저장소 관통 확인)', () async {
      final repo = FakeCharacterRepository(selectedCode: 'MONKEY', coinBalance: 100);

      // 구매: 100 → 85(HAT_CAP_BLACK 15코인).
      final afterBuy = await repo.purchaseItem('HAT_CAP_BLACK');
      expect(afterBuy.coinBalance, 85);

      // 착용: 배치 스냅샷 교체 → 내 캐릭터 equipment 에 반영.
      final equipped = await repo.replaceEquipment(const [
        EquipmentSelection(slot: 'HAT', slotIndex: 0, groupCode: 'HAT_CAP_BLACK'),
      ]);
      expect(
        equipped.equipment.any((e) => e.groupCode == 'HAT_CAP_BLACK'),
        isTrue,
      );
    });
  });
}
