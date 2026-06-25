// 프로필 조회/수정 기능 테스트.
// - User 모델 bio 직렬화(round-trip).
// - ProfileEditController: updateMe 인자(UpdateProfileRequest) 전달 + Failure 변환.
// - ProfilePage: 로딩→데이터(bio 표시).
// - ProfileEditPage: bio 300자 입력 제한, 빈 닉네임 검증.
//
// Supabase/네트워크 없이 profileRepositoryProvider를 Fake로 override해 검증한다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/core/error/failure.dart';
import 'package:record/features/profile/data/dto/update_profile_request.dart';
import 'package:record/features/profile/domain/profile_repository.dart';
import 'package:record/features/profile/presentation/profile_edit_page.dart';
import 'package:record/features/profile/presentation/profile_page.dart';
import 'package:record/features/profile/presentation/providers/profile_providers.dart';
import 'package:record/features/profile/presentation/widgets/profile_edit_image_section.dart';
import 'package:record/shared/models/user.dart';
import 'package:record/shared/widgets/profile_avatar.dart';

/// 결정적 테스트용 가짜 ProfileRepository.
class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({
    required this.user,
    this.failOnUpdate = false,
    this.failOnUpload = false,
  });

  User user;
  bool failOnUpdate;
  bool failOnUpload;
  UpdateProfileRequest? lastRequest;
  Uint8List? lastUploadedBytes;
  String? lastUploadedFilename;

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
      bio: request.bio,
    );
    return user;
  }

  @override
  Future<User> uploadAvatar(Uint8List bytes, String filename) async {
    lastUploadedBytes = bytes;
    lastUploadedFilename = filename;
    if (failOnUpload) {
      throw const Failure('INVALID_FILE', '이미지 파일만 업로드할 수 있어요.');
    }
    user = user.copyWith(profileImageUrl: '/files/avatars/2026/06/new.png');
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
        bio: '새 소개',
      );
      final updated =
          await container.read(profileEditControllerProvider.notifier).submit(req);

      expect(repo.lastRequest, isNotNull);
      expect(repo.lastRequest!.nickname, '새닉');
      expect(req.toJson()['bio'], '새 소개');
      // PUT 바디에는 profileImageUrl이 더 이상 포함되지 않는다(아바타 경로 분리).
      expect(req.toJson().containsKey('profileImageUrl'), isFalse);
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

  group('ProfileAvatar', () {
    test('initialOf는 닉네임 첫 글자(grapheme)를 반환, 빈 값이면 null', () {
      expect(ProfileAvatar.initialOf('김민수'), '김');
      expect(ProfileAvatar.initialOf('  alice '), 'a');
      expect(ProfileAvatar.initialOf(''), isNull);
      expect(ProfileAvatar.initialOf('   '), isNull);
      expect(ProfileAvatar.initialOf(null), isNull);
    });

    testWidgets('이미지가 없고 이니셜이 있으면 이니셜 텍스트를 표시', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(imageUrl: null, radius: 24, initial: '김'),
        ),
      ));

      expect(find.text('김'), findsOneWidget);
      expect(find.byType(Image), findsNothing); // 네트워크 이미지 미생성
    });

    testWidgets('이미지·이니셜 모두 없으면 사람 아이콘으로 폴백', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(imageUrl: null, radius: 24),
        ),
      ));

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('onTap이 있으면 버튼 시맨틱스로 노출되고 탭이 동작', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(
            radius: 24,
            initial: '김',
            onTap: () => tapped = true,
          ),
        ),
      ));

      await tester.tap(find.byType(ProfileAvatar));
      expect(tapped, isTrue);
    });
  });

  group('ProfileEditImageSection', () {
    testWidgets('업로드 중이면 스피너 표시 + "사진 변경" 비활성', (tester) async {
      var picked = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileEditImageSection(
            initial: '김',
            isUploading: true,
            onPickImage: () => picked = true,
          ),
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('사진 변경'));
      expect(picked, isFalse); // 업로드 중에는 콜백 미호출
    });

    testWidgets('로컬 바이트가 있으면 미리보기 이미지를 표시', (tester) async {
      // 디코딩 가능한 1x1 투명 PNG(더미 바이트는 decode 예외를 던지므로 실제 PNG 사용).
      final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4'
        '2mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileEditImageSection(
            initial: '김',
            localImageBytes: pngBytes,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget); // Image.memory 미리보기
    });

    testWidgets('"사진 변경" 탭이 onPickImage를 호출', (tester) async {
      var picked = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileEditImageSection(
            initial: '김',
            onPickImage: () => picked = true,
          ),
        ),
      ));

      await tester.tap(find.text('사진 변경'));
      expect(picked, isTrue);
    });
  });

  group('아바타 업로드(repository)', () {
    test('uploadAvatar는 바이트·파일명을 전달하고 새 이미지 경로를 반영', () async {
      final repo = _FakeProfileRepository(user: _user);
      final container = _container(repo);

      final bytes = Uint8List.fromList(const [1, 2, 3]);
      final updated = await container
          .read(profileRepositoryProvider)
          .uploadAvatar(bytes, 'a.png');

      expect(repo.lastUploadedBytes, bytes);
      expect(repo.lastUploadedFilename, 'a.png');
      expect(updated.profileImageUrl, '/files/avatars/2026/06/new.png');
    });

    test('업로드 실패 시 Failure(INVALID_FILE)로 던져진다', () async {
      final repo = _FakeProfileRepository(user: _user, failOnUpload: true);
      final container = _container(repo);

      await expectLater(
        container
            .read(profileRepositoryProvider)
            .uploadAvatar(Uint8List.fromList(const [0]), 'a.txt'),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'INVALID_FILE')),
      );
    });
  });
}
