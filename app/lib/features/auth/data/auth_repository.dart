import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';

/// Supabase Auth 기반 인증 동작. 구글(네이티브 idToken)·카카오(웹 OAuth)·로그아웃.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  static bool _googleInitialized = false;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// 구글 로그인. 플랫폼별로 경로가 갈린다.
  ///
  /// - 웹: `signInWithOAuth`(리다이렉트 방식). supabase_flutter가 현재 origin으로
  ///   콜백을 처리하므로 redirectTo를 지정하지 않는다.
  /// - 모바일: `google_sign_in`으로 idToken 획득 → `signInWithIdToken`(네이티브).
  ///   웹에서는 `GoogleSignIn.authenticate()`가 동작하지 않으므로 분리한다.
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _client.auth.signInWithOAuth(OAuthProvider.google);
      return;
    }

    await _ensureGoogleInitialized();

    final googleAccount = await GoogleSignIn.instance.authenticate();
    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('구글 ID 토큰을 가져오지 못했습니다.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: SupabaseConfig.googleIosClientId.isEmpty
          ? null
          : SupabaseConfig.googleIosClientId,
      serverClientId: SupabaseConfig.googleWebClientId.isEmpty
          ? null
          : SupabaseConfig.googleWebClientId,
    );
    _googleInitialized = true;
  }

  /// 카카오: 웹 OAuth 플로우(딥링크 콜백). 네이티브 idToken의 audience 버그 회피.
  Future<void> signInWithKakao() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.kakao,
      redirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// 이메일 회원가입.
  ///
  /// - 닉네임은 `data`(user_metadata)로 저장 → 백엔드 JIT 프로비저닝이 읽는다.
  /// - Confirm email이 켜져 있으면 응답의 `session`은 null(미인증), `user`만 채워진다.
  ///   확인 메일 링크는 [SupabaseConfig.oauthRedirect] 딥링크로 돌아온다.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {'nickname': nickname},
      emailRedirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirect,
    );
  }

  /// 이메일 로그인.
  ///
  /// 미인증 계정이면 Supabase가 `AuthException(code: 'email_not_confirmed')`를 던진다.
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// 가입 확인 메일 재전송.
  Future<void> resendConfirmationEmail(String email) {
    return _client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirect,
    );
  }

  /// 비밀번호 재설정 메일 요청.
  ///
  /// 메일의 링크를 누르면 복구 세션이 생기고 `AuthChangeEvent.passwordRecovery`가
  /// 발생한다. 웹은 현재 origin 기반 `/reset-password`로, 모바일은 딥링크로 돌아온다.
  Future<void> requestPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb
          ? '${Uri.base.origin}/reset-password'
          : SupabaseConfig.oauthRedirect,
    );
  }

  /// 현재(복구) 세션의 비밀번호를 새 값으로 변경한다.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() => _client.auth.signOut();
}
