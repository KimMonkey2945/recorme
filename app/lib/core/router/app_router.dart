import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/diary/presentation/diary_detail_page.dart';
import '../../features/diary/presentation/diary_editor_page.dart';
import '../../features/diary/presentation/diary_list_page.dart';
import '../../features/diary/presentation/main_calendar_page.dart';
import 'scaffold_with_nav_bar.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// 앱 라우터. 인증 상태에 따라 로그인/메인을 분기하는 redirect 가드를 포함한다.
final routerProvider = Provider<GoRouter>((ref) {
  // 인증 상태 변경 시 redirect를 재평가하도록 ValueNotifier로 브리지
  final refresh = ValueNotifier<AuthStatus>(ref.read(authControllerProvider));
  ref.listen<AuthStatus>(
    authControllerProvider,
    (_, next) => refresh.value = next,
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      // 개발용: --dart-define=DEV_BYPASS_AUTH=true 면 인증 가드를 건너뛴다(웹 UI 테스트용)
      if (const bool.fromEnvironment('DEV_BYPASS_AUTH')) return null;

      final status = ref.read(authControllerProvider);
      // 토큰 복원 중에는 분기 보류
      if (status == AuthStatus.unknown) return null;

      final loggingIn = state.matchedLocation == '/login';
      final authenticated = status == AuthStatus.authenticated;

      if (!authenticated) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      // 하단 탭 셸: 캘린더 / 목록
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const MainCalendarPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/list',
                builder: (context, state) => const DiaryListPage(),
              ),
            ],
          ),
        ],
      ),
      // 셸 밖 전체 화면: 에디터 / 상세
      GoRoute(
        path: '/editor',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            DiaryEditorPage(date: state.uri.queryParameters['date']),
      ),
      GoRoute(
        path: '/diary/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            DiaryDetailPage(diaryId: state.pathParameters['id']!),
      ),
    ],
  );
});
