// 이메일 가입/로그인 인증 흐름 테스트.
// - EmailAuthController: 가입 후 확인 안내 분기(session==null), 미인증 로그인 차단,
//   AuthException → Failure 한국어 매핑.
// - SignUpPage: 폼 유효성(빈 닉네임·비밀번호 불일치).
// - EmailConfirmPage: 안내 이메일 표시 + 재전송.
//
// Supabase 실서버 없이, authRepositoryProvider를 Fake로 override해 검증한다.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:record/core/error/failure.dart';
import 'package:record/features/auth/data/auth_repository.dart';
import 'package:record/features/auth/data/email_lookup_repository.dart';
import 'package:record/features/auth/presentation/email_confirm_page.dart';
import 'package:record/features/auth/presentation/providers/auth_provider.dart';
import 'package:record/features/auth/presentation/signup_page.dart';

/// 결정적 테스트용 가짜 AuthRepository.
///
/// signUp/signIn/resend의 동작을 주입한 람다로 흉내 낸다.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.onSignUp,
    this.onSignIn,
  });

  final Future<AuthResponse> Function()? onSignUp;
  final Future<AuthResponse> Function()? onSignIn;

  int resendCount = 0;
  int resetRequestCount = 0;
  String? lastUpdatedPassword;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signInWithKakao() async {}

  @override
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) =>
      (onSignUp ?? () async => AuthResponse(session: null))();

  @override
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) =>
      (onSignIn ?? () async => AuthResponse(session: null))();

  @override
  Future<void> resendConfirmationEmail(String email) async {
    resendCount++;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    resetRequestCount++;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    lastUpdatedPassword = newPassword;
  }

  @override
  Future<void> signOut() async {}
}

/// 빈 identities를 가진 gotrue User로 "이미 가입된 이메일" 가짜 성공을 흉내 낸다.
/// (여기서 `User`는 supabase_flutter가 export하는 gotrue User 타입이다.)
AuthResponse _existingEmailResponse() => AuthResponse(
      session: null,
      user: const User(
        id: 'u-existing',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        identities: [],
      ),
    );

/// 정상 신규 가입: identity 1개 보유.
AuthResponse _newEmailResponse() => AuthResponse(
      session: null,
      user: User(
        id: 'u-new',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        identities: [
          UserIdentity(
            identityId: 'i-1',
            id: 'u-new',
            userId: 'u-new',
            identityData: const {},
            provider: 'email',
            createdAt: '2026-01-01T00:00:00Z',
            lastSignInAt: '2026-01-01T00:00:00Z',
            updatedAt: '2026-01-01T00:00:00Z',
          ),
        ],
      ),
    );

/// 결정적 테스트용 가짜 이메일 조회 저장소.
/// emailExists를 override하므로 super의 Dio는 사용되지 않는다.
class _FakeEmailLookup extends EmailLookupRepository {
  _FakeEmailLookup({this.exists = true, this.throwError = false}) : super(Dio());

  final bool exists;
  final bool throwError;
  int callCount = 0;

  @override
  Future<bool> emailExists(String email) async {
    callCount++;
    if (throwError) {
      throw const Failure('NETWORK', '조회 실패');
    }
    return exists;
  }
}

ProviderContainer _container(AuthRepository repo, {EmailLookupRepository? lookup}) {
  final c = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (lookup != null)
        emailLookupRepositoryProvider.overrideWithValue(lookup),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _wrap(Widget child, AuthRepository repo) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: child),
    );

void main() {
  group('EmailAuthController', () {
    test('가입 성공(Confirm email) → 확인 안내 필요(true) 반환', () async {
      final repo = _FakeAuthRepository(
        onSignUp: () async => AuthResponse(session: null),
      );
      final container = _container(repo);

      final needsConfirm = await container
          .read(emailAuthControllerProvider.notifier)
          .submitSignUp(
            email: 'a@b.com',
            password: 'secret123',
            nickname: '테스터',
          );

      expect(needsConfirm, true);
    });

    test('미인증 로그인 → Failure(EMAIL_NOT_CONFIRMED)로 차단', () async {
      final repo = _FakeAuthRepository(
        onSignIn: () async =>
            throw const AuthException('Email not confirmed',
                code: 'email_not_confirmed'),
      );
      final container = _container(repo);

      await expectLater(
        container
            .read(emailAuthControllerProvider.notifier)
            .submitSignIn(email: 'a@b.com', password: 'secret123'),
        throwsA(
          isA<Failure>().having((f) => f.code, 'code', 'EMAIL_NOT_CONFIRMED'),
        ),
      );
    });

    test('잘못된 자격증명 → Failure(INVALID_CREDENTIALS)', () async {
      final repo = _FakeAuthRepository(
        onSignIn: () async => throw const AuthException('invalid',
            code: 'invalid_credentials'),
      );
      final container = _container(repo);

      await expectLater(
        container
            .read(emailAuthControllerProvider.notifier)
            .submitSignIn(email: 'a@b.com', password: 'wrong'),
        throwsA(
          isA<Failure>().having((f) => f.code, 'code', 'INVALID_CREDENTIALS'),
        ),
      );
    });

    test('이미 가입된 이메일 → Failure(EMAIL_EXISTS)', () async {
      final repo = _FakeAuthRepository(
        onSignUp: () async =>
            throw const AuthException('exists', code: 'user_already_exists'),
      );
      final container = _container(repo);

      await expectLater(
        container.read(emailAuthControllerProvider.notifier).submitSignUp(
              email: 'a@b.com',
              password: 'secret123',
              nickname: '테스터',
            ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'EMAIL_EXISTS')),
      );
    });

    test('중복 가입(가짜 성공: identities 빈 배열) → Failure(EMAIL_EXISTS)', () async {
      final repo = _FakeAuthRepository(onSignUp: () async => _existingEmailResponse());
      final container = _container(repo);

      await expectLater(
        container.read(emailAuthControllerProvider.notifier).submitSignUp(
              email: 'a@b.com',
              password: 'secret123',
              nickname: '테스터',
            ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'EMAIL_EXISTS')),
      );
    });

    test('정상 신규 가입(identity 보유) → 차단되지 않고 확인 안내(true)', () async {
      final repo = _FakeAuthRepository(onSignUp: () async => _newEmailResponse());
      final container = _container(repo);

      final needsConfirm =
          await container.read(emailAuthControllerProvider.notifier).submitSignUp(
                email: 'a@b.com',
                password: 'secret123',
                nickname: '테스터',
              );

      expect(needsConfirm, true);
    });
  });

  group('비밀번호 재설정', () {
    test('가입된 이메일 → 재설정 메일 발송', () async {
      final repo = _FakeAuthRepository();
      final container =
          _container(repo, lookup: _FakeEmailLookup(exists: true));

      await container
          .read(emailAuthControllerProvider.notifier)
          .requestPasswordReset('a@b.com');

      expect(repo.resetRequestCount, 1);
    });

    test('미가입 이메일 → 메일 미발송 + Failure(EMAIL_NOT_FOUND)', () async {
      final repo = _FakeAuthRepository();
      final container =
          _container(repo, lookup: _FakeEmailLookup(exists: false));

      await expectLater(
        container
            .read(emailAuthControllerProvider.notifier)
            .requestPasswordReset('ghost@b.com'),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'EMAIL_NOT_FOUND')),
      );
      // 미가입이면 발송 경로를 타지 않는다.
      expect(repo.resetRequestCount, 0);
    });

    test('사전 확인 실패(네트워크 오류) → 발송으로 폴백', () async {
      final repo = _FakeAuthRepository();
      final container =
          _container(repo, lookup: _FakeEmailLookup(throwError: true));

      await container
          .read(emailAuthControllerProvider.notifier)
          .requestPasswordReset('a@b.com');

      // 조회 실패 시 가용성 우선으로 그대로 발송한다(기존 보안 표준 동작).
      expect(repo.resetRequestCount, 1);
    });

    test('updatePassword 성공 시 복구 플래그가 해제된다', () async {
      final repo = _FakeAuthRepository();
      final container = _container(repo);

      // 복구 진행 중 상태로 만든 뒤 비밀번호 변경.
      container.read(passwordRecoveryProvider.notifier).begin();
      expect(container.read(passwordRecoveryProvider), isTrue);

      await container
          .read(emailAuthControllerProvider.notifier)
          .updatePassword('newSecret123');

      expect(repo.lastUpdatedPassword, 'newSecret123');
      expect(container.read(passwordRecoveryProvider), isFalse);
    });
  });

  group('SignUpPage 폼 유효성', () {
    testWidgets('빈 입력으로 가입 시 검증 메시지 표시', (tester) async {
      await tester.pumpWidget(_wrap(const SignUpPage(), _FakeAuthRepository()));

      await tester.tap(find.widgetWithText(FilledButton, '가입하기'));
      await tester.pump();

      expect(find.text('닉네임을 입력해주세요.'), findsOneWidget);
      expect(find.text('이메일을 입력해주세요.'), findsOneWidget);
      expect(find.text('비밀번호를 입력해주세요.'), findsOneWidget);
    });

    testWidgets('비밀번호 불일치 시 검증 메시지 표시', (tester) async {
      await tester.pumpWidget(_wrap(const SignUpPage(), _FakeAuthRepository()));

      await tester.enterText(find.byType(TextFormField).at(0), '테스터');
      await tester.enterText(find.byType(TextFormField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret123');
      await tester.enterText(find.byType(TextFormField).at(3), 'different');
      await tester.tap(find.widgetWithText(FilledButton, '가입하기'));
      await tester.pump();

      expect(find.text('비밀번호가 일치하지 않아요.'), findsOneWidget);
    });
  });

  group('EmailConfirmPage', () {
    testWidgets('안내 이메일 표시 + 재전송 호출', (tester) async {
      final repo = _FakeAuthRepository();
      await tester.pumpWidget(
        _wrap(const EmailConfirmPage(email: 'a@b.com'), repo),
      );

      expect(find.textContaining('a@b.com'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '확인 메일 다시 보내기'));
      await tester.pump();

      expect(repo.resendCount, 1);
      expect(find.text('확인 메일을 다시 보냈어요.'), findsOneWidget);
    });
  });
}
