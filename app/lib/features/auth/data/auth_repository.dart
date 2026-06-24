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

  /// 구글: google_sign_in으로 idToken 획득 → Supabase signInWithIdToken.
  Future<void> signInWithGoogle() async {
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

  Future<void> signOut() => _client.auth.signOut();
}
