import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import 'providers/feed_providers.dart';
import 'widgets/feed_diary_card.dart';
import 'widgets/feed_loading_footer.dart';

/// 피드 탭(/feed). 본인+PUBLIC+수락친구 FRIENDS 감정 카드를 무한 스크롤로 보여준다.
/// 카드 탭 시 전문(/feed/diary/:id)으로 이동한다.
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// 하단 근접 시 다음 페이지 로드.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feedProvider);

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_outlined),
              tooltip: '친구',
              onPressed: () => context.push('/friends'),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '함께 나눈 하루',
                      style: TextStyle(
                        fontFamily: 'PoorStory',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '친구들의 이야기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () => const LoadingView(message: '피드를 불러오는 중...'),
                  error: (e, _) => ErrorView(
                    message: '피드를 불러오지 못했어요',
                    onRetry: () => ref.invalidate(feedProvider),
                  ),
                  data: (state) {
                    if (state.items.isEmpty) {
                      return EmptyStateView(
                        icon: Icons.dynamic_feed_outlined,
                        message: '아직 피드에 올라온 기록이 없어요',
                        actionLabel: '친구 추가하기',
                        onAction: () => context.push('/friends/add'),
                      );
                    }
                    return RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () => ref.read(feedProvider.notifier).refresh(),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: state.items.length + 1,
                        itemBuilder: (context, i) {
                          if (i == state.items.length) {
                            return FeedLoadingFooter(visible: state.isLoadingMore);
                          }
                          final item = state.items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: FeedDiaryCard(
                              item: item,
                              onTap: () => context.push('/feed/diary/${item.id}'),
                              onReactionTap: () => ref
                                  .read(feedProvider.notifier)
                                  .toggleReaction(item),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
