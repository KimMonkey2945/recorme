import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/api_feed_repository.dart';
import '../../data/dto/feed_dto.dart';
import '../../domain/feed_repository.dart';

/// 피드 저장소 주입 지점. 테스트는 이 provider를 Fake로 override한다.
final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => ApiFeedRepository(ref.watch(dioProvider)),
);

/// 피드 무한 스크롤 상태(누적 items + 커서 + 추가 로딩 플래그).
class FeedState {
  const FeedState({
    this.items = const [],
    this.hasNext = false,
    this.nextCursor,
    this.isLoadingMore = false,
  });

  final List<FeedItem> items;
  final bool hasNext;
  final int? nextCursor;
  final bool isLoadingMore;

  FeedState copyWith({
    List<FeedItem>? items,
    bool? hasNext,
    int? nextCursor,
    bool? isLoadingMore,
  }) =>
      FeedState(
        items: items ?? this.items,
        hasNext: hasNext ?? this.hasNext,
        nextCursor: nextCursor ?? this.nextCursor,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

/// 피드 목록 Notifier. 첫 페이지 로드 + 하단 근접 시 loadMore(커서 페이징 누적).
class FeedNotifier extends AsyncNotifier<FeedState> {
  static const int _pageSize = 20;

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  @override
  Future<FeedState> build() async {
    final page = await _repo.getFeed(size: _pageSize);
    return FeedState(
      items: page.items,
      hasNext: page.hasNext,
      nextCursor: page.nextCursor,
    );
  }

  /// 다음 페이지를 이어 붙인다. 더 없거나 이미 로딩 중이면 무시.
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null ||
        !current.hasNext ||
        current.isLoadingMore ||
        current.nextCursor == null) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await _repo.getFeed(cursor: current.nextCursor, size: _pageSize);
      state = AsyncData(current.copyWith(
        items: [...current.items, ...page.items],
        hasNext: page.hasNext,
        nextCursor: page.nextCursor,
        isLoadingMore: false,
      ));
    } catch (_) {
      // 추가 로딩 실패 시 로딩 플래그만 해제하고 기존 목록은 유지(다음 스크롤에서 재시도 가능).
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// 당겨서 새로고침 — 첫 페이지부터 다시 로드.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// 공감 토글(낙관적 갱신). 즉시 목록의 해당 항목을 뒤집고, 서버 결과로 정확값 반영.
  /// 실패 시 원래 상태로 되돌린다.
  Future<void> toggleReaction(FeedItem target) async {
    final current = state.asData?.value;
    if (current == null) return;
    final wasReacted = target.reactedByMe;

    // 낙관적: 목록에서 해당 항목만 뒤집는다.
    FeedItem optimistic = target.copyWith(
      reactedByMe: !wasReacted,
      reactionCount: target.reactionCount + (wasReacted ? -1 : 1),
    );
    state = AsyncData(current.copyWith(items: _replace(current.items, optimistic)));

    try {
      final result = wasReacted
          ? await _repo.unreact(target.id)
          : await _repo.react(target.id);
      final synced = target.copyWith(
        reactedByMe: result.reacted,
        reactionCount: result.reactionCount,
      );
      final latest = state.asData?.value ?? current;
      state = AsyncData(latest.copyWith(items: _replace(latest.items, synced)));
    } catch (_) {
      // 롤백: 원래 항목으로 복구.
      final latest = state.asData?.value ?? current;
      state = AsyncData(latest.copyWith(items: _replace(latest.items, target)));
    }
  }

  /// items 에서 같은 id 항목을 [updated]로 교체한 새 리스트.
  List<FeedItem> _replace(List<FeedItem> items, FeedItem updated) =>
      [for (final it in items) it.id == updated.id ? updated : it];
}

final feedProvider =
    AsyncNotifierProvider.autoDispose<FeedNotifier, FeedState>(FeedNotifier.new);

/// 피드 카드 전문 조회(GET /feed/{id}).
final feedDetailProvider =
    FutureProvider.autoDispose.family<FeedDetail, int>((ref, id) {
  return ref.watch(feedRepositoryProvider).getDetail(id);
});
