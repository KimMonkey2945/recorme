import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../resolution/domain/resolution.dart';
import '../../data/api_friend_browse_repository.dart';
import '../../domain/friend_browse.dart';
import '../../domain/friend_browse_repository.dart';

/// 친구 둘러보기 저장소 주입 지점.
/// 테스트에서는 `ProviderScope(overrides: [...])`로 Fake를 주입한다.
final friendBrowseRepositoryProvider = Provider<FriendBrowseRepository>((ref) {
  return ApiFriendBrowseRepository(ref.watch(dioProvider));
});

/// 친구의 캐릭터 홈. family 키는 대상 친구의 uuid.
///
/// 앱의 다른 provider들이 전부 "나" 고정인 것과 달리 여기서는 대상을 키로 받는다.
/// 전부 autoDispose 라 화면을 벗어나면 남의 데이터가 메모리에 남지 않는다.
final friendCharacterProvider =
    FutureProvider.autoDispose.family<FriendCharacter, String>((ref, uuid) {
  return ref.watch(friendBrowseRepositoryProvider).getCharacter(uuid);
});

/// 친구의 월별 캘린더. 키는 (uuid, yearMonth) — Dart record 라 값 동등성으로 캐시된다.
final friendDiarySummaryProvider = FutureProvider.autoDispose
    .family<List<FriendDiaryDay>, ({String uuid, String yearMonth})>((ref, key) {
  return ref
      .watch(friendBrowseRepositoryProvider)
      .getDiarySummary(key.uuid, key.yearMonth);
});

/// 친구의 작심삼일 목록. 키는 (uuid, status).
final friendResolutionListProvider = FutureProvider.autoDispose.family<
    List<ResolutionSummaryItem>,
    ({String uuid, ResolutionStatus? status})>((ref, key) {
  return ref
      .watch(friendBrowseRepositoryProvider)
      .getResolutions(key.uuid, status: key.status);
});
