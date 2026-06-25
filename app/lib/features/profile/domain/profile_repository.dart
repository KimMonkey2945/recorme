import 'dart:typed_data';

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

  /// 프로필 수정(닉네임/자기소개). PUT /users/me
  Future<User> updateMe(UpdateProfileRequest request);

  /// 프로필 이미지 업로드(multipart). POST /users/me/avatar
  ///
  /// [bytes]는 선택한 이미지의 바이트(웹·모바일 공통), [filename]은 확장자 판별용 표시 이름.
  /// 성공 시 갱신된 [User](새 이미지 경로 포함)를 반환한다.
  Future<User> uploadAvatar(Uint8List bytes, String filename);
}
