import '../../../shared/models/user.dart';
import '../data/dto/update_profile_request.dart';

/// 프로필 데이터 접근 추상화.
///
/// diary feature와 동일하게 domain 추상 + data 구현(`ApiProfileRepository`)을
/// 분리하고, 테스트에서는 `ProviderScope(overrides: [...])`로 Fake를 주입한다.
/// 메서드 시그니처는 `docs/api-contract.md`의 `/users/me`와 1:1로 대응한다.
abstract class ProfileRepository {
  /// 현재 사용자 프로필 조회. GET /users/me
  Future<User> getMe();

  /// 프로필 수정(닉네임/이미지/자기소개). PUT /users/me
  Future<User> updateMe(UpdateProfileRequest request);
}
