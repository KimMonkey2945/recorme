/// 사용자(외부 노출 식별자 uuid 기반). api-contract의 user 객체와 1:1.
///
/// 비고: 본 프로젝트는 freezed 사용을 의도했으나, 현재 Flutter SDK(Dart 3.10)에서
/// flutter_test가 analyzer를 8.x로 고정 → build_runner 2.15.0까지만 해결되고,
/// 네이티브 빌드 훅 의존성과 결합 시 코드 생성이 막힌다. 따라서 모델은 손으로 작성한
/// 불변 클래스로 둔다. (코드 생성 재도입은 Phase 3에서 SDK/패키지 정합 후 검토)
class User {
  const User({
    required this.uuid,
    required this.nickname,
    this.email,
    this.profileImageUrl,
  });

  final String uuid;
  final String nickname;
  final String? email;
  final String? profileImageUrl;

  factory User.fromJson(Map<String, dynamic> json) => User(
        uuid: json['uuid'] as String,
        nickname: json['nickname'] as String,
        email: json['email'] as String?,
        profileImageUrl: json['profileImageUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'nickname': nickname,
        'email': email,
        'profileImageUrl': profileImageUrl,
      };

  User copyWith({
    String? uuid,
    String? nickname,
    String? email,
    String? profileImageUrl,
  }) =>
      User(
        uuid: uuid ?? this.uuid,
        nickname: nickname ?? this.nickname,
        email: email ?? this.email,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.uuid == uuid &&
      other.nickname == nickname &&
      other.email == email &&
      other.profileImageUrl == profileImageUrl;

  @override
  int get hashCode => Object.hash(uuid, nickname, email, profileImageUrl);
}
