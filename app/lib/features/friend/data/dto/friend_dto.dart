// 친구 도메인 모델(손 작성 불변 클래스 — 프로젝트 freezed 미사용 관례).
// 백엔드 /friends/* 응답과 1:1 대응한다.

/// 친구 목록 항목. [friendshipId]는 커서 페이징 키(관계 행 id).
class Friend {
  const Friend({
    required this.friendshipId,
    required this.userUuid,
    required this.nickname,
    this.profileImageUrl,
  });

  final int friendshipId;
  final String userUuid;
  final String nickname;
  final String? profileImageUrl;

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        friendshipId: (json['friendshipId'] as num).toInt(),
        userUuid: json['userUuid'] as String,
        nickname: json['nickname'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}

/// 친구 요청 항목(받은/보낸). [requestId]는 커서·수락/거절 대상 id.
/// [userUuid]는 상대(받은 요청이면 요청자, 보낸 요청이면 수신자).
class FriendRequest {
  const FriendRequest({
    required this.requestId,
    required this.userUuid,
    required this.nickname,
    this.profileImageUrl,
    this.createdAt,
  });

  final int requestId;
  final String userUuid;
  final String nickname;
  final String? profileImageUrl;
  final DateTime? createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        requestId: (json['requestId'] as num).toInt(),
        userUuid: json['userUuid'] as String,
        nickname: json['nickname'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
      );
}

/// 검색자 관점의 관계 상태.
enum FriendRelation {
  none,
  requested, // 내가 보낸 요청 대기
  incoming, // 상대가 보낸 요청 대기
  friend,
  blocked;

  static FriendRelation fromCode(String? code) => switch (code) {
        'REQUESTED' => FriendRelation.requested,
        'INCOMING' => FriendRelation.incoming,
        'FRIEND' => FriendRelation.friend,
        'BLOCKED' => FriendRelation.blocked,
        _ => FriendRelation.none,
      };
}

/// 친구 검색 결과 항목.
class FriendSearchResult {
  const FriendSearchResult({
    required this.userUuid,
    required this.nickname,
    this.profileImageUrl,
    this.relation = FriendRelation.none,
  });

  final String userUuid;
  final String nickname;
  final String? profileImageUrl;
  final FriendRelation relation;

  factory FriendSearchResult.fromJson(Map<String, dynamic> json) =>
      FriendSearchResult(
        userUuid: json['userUuid'] as String,
        nickname: json['nickname'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
        relation: FriendRelation.fromCode(json['relation'] as String?),
      );
}

/// 친구 요청 전송 결과. 상태는 보통 PENDING, 상호 요청이면 ACCEPTED(자동 수락).
class FriendRequestResult {
  const FriendRequestResult({required this.requestId, required this.status});

  final int requestId;
  final String status;

  factory FriendRequestResult.fromJson(Map<String, dynamic> json) =>
      FriendRequestResult(
        requestId: (json['requestId'] as num).toInt(),
        status: json['status'] as String,
      );

  bool get autoAccepted => status == 'ACCEPTED';
}
