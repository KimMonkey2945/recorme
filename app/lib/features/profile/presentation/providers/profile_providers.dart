import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../shared/models/user.dart';
import '../../data/api_profile_repository.dart';
import '../../data/dto/update_profile_request.dart';
import '../../domain/profile_repository.dart';

/// 프로필 저장소 주입 지점. 테스트는 이 provider를 Fake로 override한다.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ApiProfileRepository(ref.watch(dioProvider)),
);

/// 현재 사용자 프로필 조회(GET /users/me). 화면은 AsyncValue로 구독한다.
final myProfileProvider = FutureProvider<User>(
  (ref) => ref.watch(profileRepositoryProvider).getMe(),
);

/// 프로필 수정 제출 상태(로딩/에러). 전역 프로필 캐시(myProfileProvider)와 분리한다.
///
/// 성공 시 갱신된 [User]를 반환하고, 호출부가 `ref.invalidate(myProfileProvider)`로
/// 조회 캐시를 무효화한다. 에러는 [Failure](한국어 메시지)로 변환해 던진다.
class ProfileEditController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<User> submit(UpdateProfileRequest request) async {
    state = const AsyncLoading();
    try {
      final updated =
          await ref.read(profileRepositoryProvider).updateMe(request);
      state = const AsyncData(null);
      return updated;
    } on Failure catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } catch (e, st) {
      final failure = Failure('UNKNOWN', e.toString());
      state = AsyncError(failure, st);
      throw failure;
    }
  }
}

final profileEditControllerProvider =
    AsyncNotifierProvider<ProfileEditController, void>(
        ProfileEditController.new);
