import '../../../shared/models/cursor_page.dart';
import '../data/dto/friend_dto.dart';

/// 친구 데이터 접근 추상화. diary/profile과 동일하게 domain 추상 + data 구현을 분리하고,
/// 테스트는 `ProviderScope(overrides: [...])`로 Fake를 주입한다.
/// 메서드는 `docs/api-contract.md`의 `/friends/*`와 1:1로 대응한다.
abstract class FriendRepository {
  /// 친구 요청(친구코드). POST /friends/requests {friendCode}
  Future<FriendRequestResult> requestByCode(String friendCode);

  /// 친구 요청(외부 uuid, 검색 결과에서 추가). POST /friends/requests {targetUuid}
  Future<FriendRequestResult> requestByUuid(String targetUuid);

  /// 받은 요청 수락. POST /friends/requests/{id}/accept
  Future<void> accept(int requestId);

  /// 받은 요청 거절. POST /friends/requests/{id}/reject
  Future<void> reject(int requestId);

  /// 친구 목록(수락됨, 커서 페이징). GET /friends
  Future<CursorPage<Friend>> getFriends({int? cursor, int size});

  /// 친구 요청 목록(커서 페이징). direction: "incoming"(받은) | "outgoing"(보낸).
  Future<CursorPage<FriendRequest>> getRequests({
    String direction,
    int? cursor,
    int size,
  });

  /// 친구 검색(친구코드 정확 + 닉네임 부분). GET /friends/search?query=
  Future<List<FriendSearchResult>> search(String query);

  /// 친구 삭제 또는 차단. DELETE /friends/{userUuid}?block=
  Future<void> remove(String userUuid, {bool block});
}
