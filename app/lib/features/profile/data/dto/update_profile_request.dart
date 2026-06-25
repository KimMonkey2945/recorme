/// PUT /users/me 요청 바디.
///
/// - [nickname]은 필수(서버 검증: 1~50자).
/// - [profileImageUrl]/[bio]는 선택. null이면 키를 생략한다(부분 갱신 의도가 아니라,
///   백엔드가 빈 문자열→null로 정규화하므로 "지우기"는 빈 문자열을 보내는 쪽을 쓴다).
///   여기서는 입력이 없을 때(null) 전송에서 제외해 불필요한 덮어쓰기를 피한다.
class UpdateProfileRequest {
  const UpdateProfileRequest({
    required this.nickname,
    this.profileImageUrl,
    this.bio,
  });

  final String nickname;
  final String? profileImageUrl;
  final String? bio;

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (bio != null) 'bio': bio,
      };
}
