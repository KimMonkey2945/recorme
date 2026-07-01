import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/email_confirm_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/diary/presentation/diary_detail_page.dart';
import '../../features/diary/presentation/diary_editor_page.dart';
import '../../features/diary/presentation/diary_list_page.dart';
import '../../features/diary/presentation/main_calendar_page.dart';
import '../../features/profile/presentation/profile_edit_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/resolution/presentation/resolution_detail_page.dart';
import '../../features/resolution/presentation/resolution_new_page.dart';
import '../../features/resolution/presentation/resolution_tab_page.dart';
import 'scaffold_with_nav_bar.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// 미인증 상태에서도 접근 가능한 공개 경로.
/// 이메일 가입 흐름(가입 화면·확인 메일 안내)과 비밀번호 찾기를 포함한다.
const _publicRoutes = {
  '/login',
  '/signup',
  '/signup/confirm',
  '/forgot-password',
};

/// 앱 라우터. 인증 상태에 따라 로그인/메인을 분기하는 redirect 가드를 포함한다.
final routerProvider = Provider<GoRouter>((ref) {
  // 인증 상태/비밀번호 복구 플래그 변경 시 redirect를 재평가하도록 브리지.
  // (둘 중 무엇이 바뀌든 카운터를 증가시켜 GoRouter가 redirect를 다시 돌린다.)
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthStatus>(authControllerProvider, (_, _) => refresh.value++);
  ref.listen<bool>(passwordRecoveryProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      // 개발용: --dart-define=DEV_BYPASS_AUTH=true 면 인증 가드를 건너뛴다(웹 UI 테스트용)
      if (const bool.fromEnvironment('DEV_BYPASS_AUTH')) return null;

      // 비밀번호 복구 중에는 세션 유무와 무관하게 재설정 화면으로 강제 유도한다.
      // (일반 authenticated 가드보다 우선)
      if (ref.read(passwordRecoveryProvider)) {
        return state.matchedLocation == '/reset-password'
            ? null
            : '/reset-password';
      }

      final status = ref.read(authControllerProvider);
      // 토큰 복원 중에는 분기 보류
      if (status == AuthStatus.unknown) return null;

      final onPublic = _publicRoutes.contains(state.matchedLocation);
      final authenticated = status == AuthStatus.authenticated;

      // 미인증: 공개 경로만 허용, 그 외는 로그인으로.
      if (!authenticated) return onPublic ? null : '/login';
      // 인증됨: 공개(인증) 경로 접근 시 메인으로.
      if (onPublic) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(
        path: '/signup/confirm',
        builder: (context, state) =>
            EmailConfirmPage(email: state.extra as String?),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordPage(),
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
          // 3번째 탭: 작심삼일
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/resolution',
                builder: (context, state) => const ResolutionTabPage(),
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
      // 셸 밖 전체 화면: 작심삼일 생성 / 상세
      GoRoute(
        path: '/resolution/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ResolutionNewPage(date: state.uri.queryParameters['date']),
      ),
      GoRoute(
        path: '/resolution/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ResolutionDetailPage(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
      // 셸 밖 전체 화면: 프로필 조회 / 수정
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileEditPage(),
      ),
    ],
  );
});
