import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/auth_repository.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// 인증 상태. Supabase 세션 유무로만 결정된다.
///
/// 이메일 미인증 상태는 "세션 없음(= unauthenticated)"으로 흡수하고, 가입 직후
/// 안내 UX는 라우팅으로 처리한다. 즉 이 enum을 미인증 표현으로 오염시키지 않는다.
enum AuthStatus { unknown, authenticated, unauthenticated }

/// 비밀번호 복구(재설정) 진행 플래그.
///
/// `AuthChangeEvent.passwordRecovery` 발생 시 켜지고, 새 비밀번호 저장 완료 시 꺼진다.
/// 복구 중에는 세션이 있어도 일반 인증 가드와 분리해 `/reset-password`로 유도한다.
/// 즉 [AuthStatus]를 오염시키지 않고 별도 신호로 표현한다.
class PasswordRecoveryController extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() => state = true;
  void complete() => state = false;
}

final passwordRecoveryProvider =
    NotifierProvider<PasswordRecoveryController, bool>(
        PasswordRecoveryController.new);

/// Supabase 세션을 구독해 인증 상태를 노출하고, 로그인/로그아웃을 위임한다.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    final repo = ref.watch(authRepositoryProvider);

    // onAuthStateChange는 구독 시 현재 세션(initialSession)도 즉시 방출한다.
    final sub = repo.onAuthStateChange.listen((authState) {
      // 비밀번호 복구 이벤트: 복구 세션이 있어도 "인증 전이"로 취급하지 않는다.
      // 인증 상태/워밍업을 건드리지 않고 복구 플래그만 켜서 라우터가
      // /reset-password로 유도하게 한다(워밍업 오인 방지).
      if (authState.event == AuthChangeEvent.passwordRecovery) {
        Future.microtask(
          () => ref.read(passwordRecoveryProvider.notifier).begin(),
        );
        return;
      }

      final hasSession = authState.session != null;
      state = hasSession
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
      // 로그인 즉시 백엔드 JIT 프로비저닝을 워밍업한다(프로필 진입 없이 users 저장).
      // - signedIn: 같은 페이지 로그인(이메일/비번).
      // - initialSession: 앱 시작 또는 OAuth(구글) 리다이렉트 후 복원된 세션.
      //   구글 웹 로그인은 리다이렉트로 앱이 재로드돼 "전이"가 없으므로, 전이 비교가
      //   아니라 이벤트 타입으로 판정해야 놓치지 않는다.
      // tokenRefreshed/userUpdated 등은 워밍업 제외(멱등이라 무해하나 중복 회피).
      if (hasSession &&
          (authState.event == AuthChangeEvent.signedIn ||
              authState.event == AuthChangeEvent.initialSession)) {
        _provisionUser();
      }
    });
    ref.onDispose(sub.cancel);

    return repo.currentSession != null
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
  }

  Future<void> signInWithGoogle() =>
      ref.read(authRepositoryProvider).signInWithGoogle();

  Future<void> signInWithKakao() =>
      ref.read(authRepositoryProvider).signInWithKakao();

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) =>
      ref.read(authRepositoryProvider).signUpWithEmail(
            email: email,
            password: password,
            nickname: nickname,
          );

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) =>
      ref
          .read(authRepositoryProvider)
          .signInWithEmail(email: email, password: password);

  Future<void> resendConfirmationEmail(String email) =>
      ref.read(authRepositoryProvider).resendConfirmationEmail(email);

  Future<void> requestPasswordReset(String email) =>
      ref.read(authRepositoryProvider).requestPasswordReset(email);

  Future<void> updatePassword(String newPassword) =>
      ref.read(authRepositoryProvider).updatePassword(newPassword);

  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();

  /// 로그인 직후 `GET /users/me`를 1회 호출해 백엔드 JIT 프로비저닝을 트리거한다.
  /// 프로필 화면 진입 없이도 인증 즉시 `users` 행이 생성된다. 실패는 무시하고
  /// (다음 프로필 진입 때 자연히 재시도) 성공 시 조회 캐시를 갱신한다.
  /// JIT는 멱등(ON CONFLICT DO NOTHING)이라 중복 호출도 안전하다.
  void _provisionUser() {
    ref.read(profileRepositoryProvider).getMe().then((_) {
      ref.invalidate(myProfileProvider);
    }).catchError((_) {});
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);

/// 이메일 가입/로그인 폼의 제출 상태(로딩/에러)를 담당한다.
///
/// 전역 [AuthStatus]와 분리한다: 로그인 성공 시 Supabase 세션이 생기면
/// [AuthController]가 자동으로 상태를 전이시키고, 여기서는 폼 제출의
/// 진행/실패만 표현한다. 에러는 [Failure](한국어 메시지)로 변환해 전달한다.
class EmailAuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// 회원가입 제출.
  ///
  /// 반환값: 확인 메일 안내 화면으로 보내야 하는지 여부.
  /// Confirm email이 켜져 있으면 응답 `session`이 null이므로 true를 돌려준다.
  Future<bool> submitSignUp({
    required String email,
    required String password,
    required String nickname,
  }) async {
    state = const AsyncLoading();
    try {
      final res =
          await ref.read(authControllerProvider.notifier).signUpWithEmail(
                email: email,
                password: password,
                nickname: nickname,
              );
      // Email enumeration protection가 켜져 있으면 중복 가입이 "가짜 성공"으로
      // 돌아온다(에러 없이 user 반환). 공식 감지법: user.identities가 빈 리스트면
      // 이미 가입된 이메일이다. (protection OFF인 경우는 mapAuthError의
      // user_already_exists/email_exists 매핑이 담당 — 양쪽 케이스 모두 커버)
      final identities = res.user?.identities;
      if (identities != null && identities.isEmpty) {
        const failure = Failure('EMAIL_EXISTS', '이미 가입된 이메일이에요.');
        state = AsyncError(failure, StackTrace.current);
        throw failure;
      }
      state = const AsyncData(null);
      return res.session == null;
    } on AuthException catch (e, st) {
      final failure = mapAuthError(e);
      state = AsyncError(failure, st);
      throw failure;
    }
  }

  /// 로그인 제출. 미인증 계정이면 [Failure]('EMAIL_NOT_CONFIRMED')로 변환된다.
  Future<void> submitSignIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signInWithEmail(email: email, password: password);
      state = const AsyncData(null);
    } on AuthException catch (e, st) {
      final failure = mapAuthError(e);
      state = AsyncError(failure, st);
      throw failure;
    }
  }

  /// 확인 메일 재전송.
  Future<void> resend(String email) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(authControllerProvider.notifier)
          .resendConfirmationEmail(email);
      state = const AsyncData(null);
    } on AuthException catch (e, st) {
      final failure = mapAuthError(e);
      state = AsyncError(failure, st);
      throw failure;
    }
  }

  /// 비밀번호 재설정 메일 요청.
  Future<void> requestPasswordReset(String email) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(email);
      state = const AsyncData(null);
    } on AuthException catch (e, st) {
      final failure = mapAuthError(e);
      state = AsyncError(failure, st);
      throw failure;
    }
  }

  /// 새 비밀번호 저장(복구 세션). 성공 시 복구 플래그를 해제한다.
  Future<void> updatePassword(String newPassword) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updatePassword(newPassword);
      ref.read(passwordRecoveryProvider.notifier).complete();
      state = const AsyncData(null);
    } on AuthException catch (e, st) {
      final failure = mapAuthError(e);
      state = AsyncError(failure, st);
      throw failure;
    }
  }
}

final emailAuthControllerProvider =
    AsyncNotifierProvider<EmailAuthController, void>(EmailAuthController.new);

/// Supabase [AuthException.code] → 한국어 메시지 [Failure] 매핑.
///
/// code 우선 매핑하고, 미정의 code는 원본 message로 폴백한다(SDK 버전 방어).
Failure mapAuthError(AuthException e) {
  switch (e.code) {
    case 'email_not_confirmed':
      return const Failure('EMAIL_NOT_CONFIRMED', '이메일 인증을 먼저 완료해주세요.');
    case 'invalid_credentials':
      return const Failure('INVALID_CREDENTIALS', '이메일 또는 비밀번호가 올바르지 않아요.');
    case 'user_already_exists':
    case 'email_exists':
      return const Failure('EMAIL_EXISTS', '이미 가입된 이메일이에요.');
    case 'weak_password':
      return const Failure('WEAK_PASSWORD', '비밀번호가 너무 약해요. 더 복잡하게 입력해주세요.');
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return const Failure('RATE_LIMIT', '요청이 많아요. 잠시 후 다시 시도해주세요.');
    default:
      return Failure(e.code ?? 'AUTH_ERROR', e.message);
  }
}
