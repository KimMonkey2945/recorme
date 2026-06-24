import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth_repository.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// 인증 상태. Supabase 세션 유무로 결정된다.
enum AuthStatus { unknown, authenticated, unauthenticated }

/// Supabase 세션을 구독해 인증 상태를 노출하고, 소셜 로그인/로그아웃을 위임한다.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    final repo = ref.watch(authRepositoryProvider);

    // onAuthStateChange는 구독 시 현재 세션(initialSession)도 즉시 방출한다.
    final sub = repo.onAuthStateChange.listen((authState) {
      state = authState.session != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
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

  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
