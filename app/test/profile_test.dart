// 프로필 조회/수정 기능 테스트.
// - User 모델 bio 직렬화(round-trip).
// - ProfileEditController: updateMe 인자(UpdateProfileRequest) 전달 + Failure 변환.
// - ProfilePage: 로딩→데이터(bio 표시).
// - ProfileEditPage: bio 300자 입력 제한, 빈 닉네임 검증.
//
// Supabase/네트워크 없이 profileRepositoryProvider를 Fake로 override해 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/core/error/failure.dart';
import 'package:record/features/profile/data/dto/update_profile_request.dart';
import 'package:record/features/profile/domain/profile_repository.dart';
import 'package:record/features/profile/presentation/profile_edit_page.dart';
import 'package:record/features/profile/presentation/profile_page.dart';
import 'package:record/features/profile/presentation/providers/profile_providers.dart';
import 'package:record/shared/models/user.dart';

/// 결정적 테스트용 가짜 ProfileRepository.
class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({required this.user, this.failOnUpdate = false});

  User user;
  bool failOnUpdate;
  UpdateProfileRequest? lastRequest;

  @override
  Future<User> getMe() async => user;

  @override
  Future<User> updateMe(UpdateProfileRequest request) async {
    lastRequest = request;
    if (failOnUpdate) {
      throw const Failure('VALIDATION_ERROR', '입력값을 확인해주세요.');
    }
    user = user.copyWith(
      nickname: request.nickname,
      profileImageUrl: request.profileImageUrl,
      bio: request.bio,
    );
    return user;
  }
}

const _user = User(
  uuid: 'u-1',
  nickname: '테스터',
  email: 'a@b.com',
  profileImageUrl: null,
  bio: '한 줄 소개입니다',
);

ProviderContainer _container(ProfileRepository repo) {
  final c = ProviderContainer(
    overrides: [profileRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _wrap(Widget child, ProfileRepository repo) => ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: child),
    );

void main() {
  group('User 모델 bio', () {
    test('fromJson/toJson round-trip에 bio가 보존된다', () {
      final json = {
        'uuid': 'u-1',
        'nickname': '테스터',
        'email': 'a@b.com',
        'profileImageUrl': 'https://img/x.png',
        'bio': '자기소개',
      };
      final user = User.fromJson(json);
      expect(user.bio, '자기소개');
      expect(user.toJson()['bio'], '자기소개');
    });

    test('bio 없으면 null', () {
      final user = User.fromJson({'uuid': 'u', 'nickname': 'n'});
      expect(user.bio, isNull);
    });

    test('copyWith로 bio 갱신, == 반영', () {
      const a = User(uuid: 'u', nickname: 'n', bio: 'x');
      final b = a.copyWith(bio: 'y');
      expect(b.bio, 'y');
      expect(a == b, isFalse);
      expect(a == a.copyWith(), isTrue);
    });
  });

  group('ProfileEditController', () {
    test('submit이 UpdateProfileRequest를 그대로 저장소에 전달', () async {
      final repo = _FakeProfileRepository(user: _user);
      final container = _container(repo);

      const req = UpdateProfileRequest(
        nickname: '새닉',
        profileImageUrl: 'https://img/y.png',
        bio: '새 소개',
      );
      final updated =
          await container.read(profileEditControllerProvider.notifier).submit(req);

      expect(repo.lastRequest, isNotNull);
      expect(repo.lastRequest!.nickname, '새닉');
      expect(req.toJson()['bio'], '새 소개');
      expect(updated.nickname, '새닉');
      expect(updated.bio, '새 소개');
    });

    test('실패 시 Failure로 변환되어 던져진다', () async {
      final repo = _FakeProfileRepository(user: _user, failOnUpdate: true);
      final container = _container(repo);

      await expectLater(
        container.read(profileEditControllerProvider.notifier).submit(
              const UpdateProfileRequest(nickname: '새닉'),
            ),
        throwsA(
          isA<Failure>().having((f) => f.code, 'code', 'VALIDATION_ERROR'),
        ),
      );
    });
  });

  group('ProfilePage', () {
    testWidgets('로딩 후 데이터(닉네임·bio) 표시', (tester) async {
      final repo = _FakeProfileRepository(user: _user);
      await tester.pumpWidget(_wrap(const ProfilePage(), repo));

      // 첫 프레임: 로딩
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('테스터'), findsOneWidget);
      expect(find.text('한 줄 소개입니다'), findsOneWidget);
      expect(find.text('a@b.com'), findsOneWidget);
    });
  });

  group('ProfileEditPage', () {
    testWidgets('빈 닉네임 저장 시 검증 메시지', (tester) async {
      final repo = _FakeProfileRepository(user: _user);
      // 프리필을 위해 myProfileProvider를 미리 로드.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: ProfileEditPage()),
        ),
      );
      await tester.pump();

      // 닉네임을 비운 뒤 저장.
      await tester.enterText(find.byType(TextFormField).at(0), '');
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pump();

      expect(find.text('닉네임을 입력해주세요.'), findsOneWidget);
    });

    testWidgets('bio 입력은 300자로 제한된다', (tester) async {
      final repo = _FakeProfileRepository(user: _user);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: ProfileEditPage()),
        ),
      );
      await tester.pump();

      // bio 필드(maxLength 지정된 TextFormField)에 400자 입력 시도.
      final longText = 'a' * 400;
      final bioField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength == ProfileEditPage.bioMaxLength,
      );
      expect(bioField, findsOneWidget);

      await tester.enterText(bioField, longText);
      await tester.pump();

      final widget = tester.widget<TextField>(bioField);
      expect(widget.controller!.text.length, ProfileEditPage.bioMaxLength);
    });
  });
}
