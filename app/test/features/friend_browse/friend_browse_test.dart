// 친구 둘러보기(읽기 전용) 테스트.
// - 상단 탭 3개(홈/캘린더/작심삼일) 구성.
// - 친구가 캐릭터 미선택이면 빈 상태.
// - 캘린더: 공개 기록만 점이 찍히고, 날짜 탭 시 viewer-aware 상세(/feed/diary/:id)로 이동.
//   비공개(=목록에 없는 날) 탭은 아무 동작도 하지 않는다.
// - 작심삼일: 타일을 눌러도 상세로 가지 않는다(쓰기 화면 진입 금지).
// - ★ 쓰기 진입점이 화면에 하나도 없다(읽기 전용 보장의 테스트 표현).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:record/core/theme/app_theme.dart';
import 'package:record/features/character/presentation/widgets/idle_character_view.dart';
import 'package:record/features/diary/data/dto/diary_dto.dart';
import 'package:record/features/friend_browse/data/fake_friend_browse_repository.dart';
import 'package:record/features/friend_browse/domain/friend_browse.dart';
import 'package:record/features/friend_browse/presentation/friend_browse_page.dart';
import 'package:record/features/friend_browse/presentation/providers/friend_browse_providers.dart';
import 'package:record/features/resolution/presentation/widgets/resolution_list_tile.dart';

const _uuid = '11111111-1111-1111-1111-111111111111';

/// 둘러보기 화면 + 이동 목적지를 추적하는 최소 라우터.
Widget _app(
  FakeFriendBrowseRepository repo, {
  List<String>? visited,
}) {
  final router = GoRouter(
    initialLocation: '/friends/browse/$_uuid',
    routes: [
      GoRoute(
        path: '/friends/browse/:userUuid',
        builder: (context, state) => FriendBrowsePage(
          userUuid: state.pathParameters['userUuid']!,
          nickname: '민수',
        ),
      ),
      GoRoute(
        path: '/feed/diary/:id',
        builder: (context, state) {
          visited?.add('/feed/diary/${state.pathParameters['id']}');
          return const Scaffold(body: Text('피드 상세'));
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [friendBrowseRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}

void main() {
  // 캐릭터 idle 애니메이션은 무한 반복이라 pumpAndSettle이 끝나지 않는다.
  setUpAll(() => IdleCharacterView.debugDisableIdleAnimation = true);
  tearDownAll(() => IdleCharacterView.debugDisableIdleAnimation = false);

  group('FriendBrowsePage', () {
    testWidgets('상단 탭 3개(홈/캘린더/작심삼일)를 렌더한다', (tester) async {
      await tester.pumpWidget(_app(FakeFriendBrowseRepository()));
      await tester.pumpAndSettle();

      expect(find.text('홈'), findsOneWidget);
      expect(find.text('캘린더'), findsOneWidget);
      expect(find.text('작심삼일'), findsOneWidget);
      expect(find.text('민수님의 recorme'), findsOneWidget);
    });

    testWidgets('쓰기 진입점이 하나도 없다', (tester) async {
      await tester.pumpWidget(_app(FakeFriendBrowseRepository()));
      await tester.pumpAndSettle();

      // 내 홈/캘린더/작심삼일에 있는 쓰기·설정 액션이 둘러보기에는 존재하면 안 된다.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('옷장'), findsNothing);
      expect(find.text('이달의 기록'), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('친구가 캐릭터 미선택이면 빈 상태를 보여준다', (tester) async {
      await tester.pumpWidget(
        _app(FakeFriendBrowseRepository(character: null)),
      );
      await tester.pumpAndSettle();

      expect(find.text('아직 캐릭터를 고르지 않았어요'), findsOneWidget);
    });

    testWidgets('캐릭터를 고른 친구는 이름이 보인다', (tester) async {
      await tester.pumpWidget(_app(FakeFriendBrowseRepository()));
      await tester.pumpAndSettle();

      expect(find.text('몽키'), findsOneWidget);
    });
  });

  group('캘린더 탭', () {
    /// 이번 달 5일에 공개 기록 1건만 있는 저장소.
    FakeFriendBrowseRepository repoWithOneDay() {
      final now = DateTime.now();
      final ym = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      return FakeFriendBrowseRepository(
        diaryDays: [
          FriendDiaryDay(
            diaryId: 777,
            summary: DiarySummaryDay(
              date: '$ym-05',
              analysisStatus: 'DONE',
              primaryEmotion: 'JOY',
            ),
          ),
        ],
      );
    }

    testWidgets('공개 기록이 있는 날짜를 탭하면 피드 상세로 간다', (tester) async {
      final visited = <String>[];
      await tester.pumpWidget(_app(repoWithOneDay(), visited: visited));
      await tester.pumpAndSettle();

      await tester.tap(find.text('캘린더'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();

      expect(visited, ['/feed/diary/777']);
    });

    testWidgets('기록 없는 날짜 탭은 아무 동작도 하지 않는다', (tester) async {
      // 비공개(PRIVATE) 기록이 있는 날도 서버가 안 내려주므로 이 경로를 탄다.
      final visited = <String>[];
      await tester.pumpWidget(_app(repoWithOneDay(), visited: visited));
      await tester.pumpAndSettle();

      await tester.tap(find.text('캘린더'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('7')); // 기록이 없는 날
      await tester.pumpAndSettle();

      expect(visited, isEmpty);
    });
  });

  group('작심삼일 탭', () {
    testWidgets('목록을 보여주되 타일은 탭 불가다', (tester) async {
      await tester.pumpWidget(_app(FakeFriendBrowseRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('작심삼일'));
      await tester.pumpAndSettle();

      expect(find.text('매일 산책하기'), findsOneWidget);

      // onTap 을 넘기지 않았으므로 상세(쓰기 가능 화면)로 갈 수 없다.
      final tile = tester.widget<ResolutionListTile>(
        find.byType(ResolutionListTile),
      );
      expect(tile.onTap, isNull);
    });

    testWidgets('도전 기록이 없으면 빈 상태', (tester) async {
      await tester.pumpWidget(
        _app(FakeFriendBrowseRepository(resolutions: const [])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('작심삼일'));
      await tester.pumpAndSettle();

      expect(find.text('아직 도전한 작심삼일이 없어요'), findsOneWidget);
    });
  });

}
// 하단 탭(브랜치 index 3 = /friends)의 정합은 character_onboarding_redirect_test 의
// '탭 브랜치 순서' 테스트가 실제 라우터를 대상으로 지킨다 — 여기서 중복 검증하지 않는다.
