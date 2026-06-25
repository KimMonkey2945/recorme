/// PUT /users/me 요청 바디(닉네임·자기소개).
///
/// - [nickname]은 필수(서버 검증: 1~50자).
/// - [bio]는 선택. null이면 키를 생략한다(빈 문자열→null 정규화는 백엔드가 수행).
///
/// 프로필 이미지는 이 요청에서 다루지 않는다 — 별도 업로드 엔드포인트
/// (`ProfileRepository.uploadAvatar`)에서만 갱신하므로 닉네임/자기소개 수정이
/// 아바타를 덮어쓰지 않는다.
class UpdateProfileRequest {
  const UpdateProfileRequest({
    required this.nickname,
    this.bio,
  });

  final String nickname;
  final String? bio;

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        if (bio != null) 'bio': bio,
      };
}
