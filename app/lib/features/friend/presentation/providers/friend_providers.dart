import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/api_friend_repository.dart';
import '../../data/dto/friend_dto.dart';
import '../../domain/friend_repository.dart';

/// 친구 저장소 주입 지점. 테스트는 이 provider를 Fake로 override한다.
final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => ApiFriendRepository(ref.watch(dioProvider)),
);

/// 친구 목록(첫 페이지). 쓰기 후 `ref.invalidate(friendsProvider)`로 갱신한다.
/// MVP 규모상 첫 페이지(최대 50건)로 충분하며, 무한 스크롤은 후속 과제.
final friendsProvider = FutureProvider.autoDispose<List<Friend>>(
  (ref) async =>
      (await ref.watch(friendRepositoryProvider).getFriends(size: 50)).items,
);

/// 받은 친구 요청(첫 페이지). 수락/거절 후 invalidate 로 갱신.
final incomingRequestsProvider =
    FutureProvider.autoDispose<List<FriendRequest>>(
  (ref) async => (await ref
          .watch(friendRepositoryProvider)
          .getRequests(direction: 'incoming', size: 50))
      .items,
);

/// 보낸 친구 요청(첫 페이지).
final outgoingRequestsProvider =
    FutureProvider.autoDispose<List<FriendRequest>>(
  (ref) async => (await ref
          .watch(friendRepositoryProvider)
          .getRequests(direction: 'outgoing', size: 50))
      .items,
);

/// 받은 요청 개수(친구 화면 요청함 배지용). 로딩/에러 시 0.
final pendingRequestCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(incomingRequestsProvider).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
});

/// 닉네임/친구코드 검색 결과(query 별). 빈 질의는 저장소에서 빈 목록.
final friendSearchProvider = FutureProvider.autoDispose
    .family<List<FriendSearchResult>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];
  return ref.watch(friendRepositoryProvider).search(trimmed);
});
