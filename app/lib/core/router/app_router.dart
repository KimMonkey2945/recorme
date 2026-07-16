import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/email_confirm_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/character/domain/my_character.dart';
import '../../features/character/presentation/character_home_page.dart';
import '../../features/character/presentation/character_onboarding_page.dart';
import '../../features/character/presentation/providers/character_providers.dart';
import '../../features/character/presentation/retrospect_page.dart';
import '../../features/character/presentation/rewards_page.dart';
import '../../features/character/presentation/wardrobe_page.dart';
import '../../features/diary/presentation/diary_detail_page.dart';
import '../../features/diary/presentation/diary_editor_page.dart';
import '../../features/diary/presentation/diary_list_page.dart';
import '../../features/diary/presentation/main_calendar_page.dart';
import '../../features/feed/presentation/feed_diary_detail_page.dart';
import '../../features/feed/presentation/feed_page.dart';
import '../../features/friend/presentation/add_friend_page.dart';
import '../../features/friend/presentation/friend_requests_page.dart';
import '../../features/friend/presentation/friends_list_page.dart';
import '../../features/profile/presentation/profile_edit_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/resolution/presentation/resolution_detail_page.dart';
import '../../features/resolution/presentation/resolution_edit_page.dart';
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

/// 캐릭터 선택 온보딩 경로(셸 밖 풀스크린).
const characterOnboardingRoute = '/onboarding/character';

/// 캐릭터 온보딩 가드의 **순수 판정 함수**(redirect에서 async 호출 금지 → 상태만 보고 판단).
///
/// [myCharacter]는 `myCharacterProvider`의 현재 값이며 의미는 다음과 같다.
/// - `null`: 아직 판단 불가(미인증 · 조회 중 · 조회 실패) → **분기 보류**(null 반환).
///   실패했다고 온보딩에 가두지 않는다.
/// - `character == null`: 인증됐고 캐릭터 미선택 → 온보딩으로 보낸다.
///   단, **이미 온보딩에 있으면 null**을 돌려 리다이렉트 루프를 막는다.
/// - `character != null`: 선택 완료 → 일반 경로는 그대로 두고(리다이렉트 없음),
///   온보딩에 재진입해 있으면 메인으로 돌려보낸다.
@visibleForTesting
String? characterOnboardingRedirect({
  required MyCharacter? myCharacter,
  required String location,
}) {
  final onOnboarding = location == characterOnboardingRoute;

  // 판단 불가(미인증·로딩·에러): 아무 분기도 하지 않는다.
  if (myCharacter == null) return null;

  // 미선택: 온보딩으로. (온보딩 자체는 루프 방지를 위해 통과)
  if (!myCharacter.hasSelection) {
    return onOnboarding ? null : characterOnboardingRoute;
  }

  // 선택 완료: 일반 경로는 리다이렉트 없음. 온보딩 재진입만 메인으로.
  return onOnboarding ? '/' : null;
}

/// 앱 라우터. 인증 상태에 따라 로그인/메인을 분기하는 redirect 가드를 포함한다.
final routerProvider = Provider<GoRouter>((ref) {
  // 인증 상태/비밀번호 복구 플래그/내 캐릭터 변경 시 redirect를 재평가하도록 브리지.
  // (무엇이 바뀌든 카운터를 증가시켜 GoRouter가 redirect를 다시 돌린다.)
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthStatus>(authControllerProvider, (_, _) => refresh.value++);
  ref.listen<bool>(passwordRecoveryProvider, (_, _) => refresh.value++);
  // 캐릭터 조회가 끝나면(로딩 → 데이터) 온보딩 가드를 다시 평가한다.
  // myCharacterProvider는 미인증이면 네트워크 호출 없이 즉시 null을 돌려준다.
  ref.listen<AsyncValue<MyCharacter?>>(
    myCharacterProvider,
    (_, _) => refresh.value++,
  );
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

      // 캐릭터 미선택자는 온보딩으로. 조회 중/실패면 보류(null)한다.
      // async 호출 없이 provider의 현재 값(AsyncValue)만 읽는다.
      return characterOnboardingRedirect(
        // asData: 데이터가 도착한 경우에만 값을 준다(로딩·에러면 null → 보류).
        myCharacter: ref.read(myCharacterProvider).asData?.value,
        location: state.matchedLocation,
      );
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
      // 셸 밖 전체 화면: 캐릭터 선택 온보딩(탭 없이 몰입)
      GoRoute(
        path: characterOnboardingRoute,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CharacterOnboardingPage(),
      ),
      // 하단 탭 셸: 캐릭터(홈) / 캘린더 / 작심삼일 / 피드 / 프로필
      // ⚠️ 브랜치 순서 = 탭 인덱스 = scaffold_with_nav_bar.dart의 destinations 순서.
      //    세 곳을 항상 함께 맞춘다(한쪽만 바꾸면 라벨·아이콘과 화면이 어긋난다).
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          // 0번째 탭: 캐릭터 홈(로그인 후 첫 화면, `/`)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const CharacterHomePage(),
              ),
            ],
          ),
          // 1번째 탭: 캘린더
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const MainCalendarPage(),
              ),
            ],
          ),
          // 2번째 탭: 작심삼일
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/resolution',
                builder: (context, state) => const ResolutionTabPage(),
              ),
            ],
          ),
          // 3번째 탭: 피드
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feed',
                builder: (context, state) => const FeedPage(),
              ),
            ],
          ),
          // 4번째 탭: 프로필(기존 셸 밖 라우트에서 탭으로 승격)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
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
        builder: (context, state) => DiaryDetailPage(
          diaryId: state.pathParameters['id']!,
          // 확정 직후 진입(editor 가 reaction=1 로 push)이면 리액션 오버레이를 띄운다(Task 032).
          showReaction: state.uri.queryParameters['reaction'] == '1',
        ),
      ),
      // 셸 밖 전체 화면: 작심삼일 생성 / 상세
      GoRoute(
        path: '/resolution/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ResolutionNewPage(date: state.uri.queryParameters['date']),
      ),
      GoRoute(
        path: '/resolution/:id/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ResolutionEditPage(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
      GoRoute(
        path: '/resolution/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ResolutionDetailPage(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
      // 셸 밖 전체 화면: 옷장(캐릭터 꾸미기) — 캐릭터 홈 탭에서 진입한다.
      GoRoute(
        path: '/wardrobe',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WardrobePage(),
      ),
      // 셸 밖 전체 화면: 보상함(미확인 보상 확인) — 홈 상태바 배지에서 진입한다.
      GoRoute(
        path: '/rewards',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RewardsPage(),
      ),
      // 셸 밖 전체 화면: 월간 회고(락인) — 캐릭터 홈에서 진입한다.
      GoRoute(
        path: '/retrospect',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => RetrospectPage(
          initialYearMonth: state.uri.queryParameters['yearMonth'],
        ),
      ),
      // 셸 밖 전체 화면: 지난 기록 목록(캘린더 앱바에서 진입).
      // 탭에서 빠지면서 셸 밖 push 라우트가 됐다(AppBar leading 미지정 → 뒤로가기 자동).
      GoRoute(
        path: '/list',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DiaryListPage(),
      ),
      // 셸 밖 전체 화면: 프로필 수정(프로필 조회는 탭, 수정은 풀스크린).
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileEditPage(),
      ),
      // 셸 밖 전체 화면: 친구 목록 / 요청함 / 추가
      GoRoute(
        path: '/friends',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FriendsListPage(),
      ),
      GoRoute(
        path: '/friends/requests',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FriendRequestsPage(),
      ),
      GoRoute(
        path: '/friends/add',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AddFriendPage(),
      ),
      // 셸 밖 전체 화면: 피드 카드 전문(타인 글 포함, viewer-aware)
      GoRoute(
        path: '/feed/diary/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            FeedDiaryDetailPage(diaryId: state.pathParameters['id']!),
      ),
    ],
  );
});
