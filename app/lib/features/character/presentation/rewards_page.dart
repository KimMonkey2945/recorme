import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/reward.dart';
import 'providers/character_providers.dart';

/// 보상함(/rewards, 셸 밖 풀스크린) — 미확인 보상(코인 적립·리액션)을 최신순으로 보여준다.
///
/// 상단 "모두 확인"으로 [ackRewardsControllerProvider]를 호출하면 서버에서 ack 처리되고,
/// 내 캐릭터(홈 배지)와 이 목록이 invalidate돼 배지가 사라지고 목록이 비워진다.
/// 홈 상태바의 보상 배지를 탭하면 진입한다([character_home_page]).
class RewardsPage extends ConsumerStatefulWidget {
  const RewardsPage({super.key});

  @override
  ConsumerState<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends ConsumerState<RewardsPage> {
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
      ref.read(rewardsProvider.notifier).loadMore();
    }
  }

  Future<void> _ackAll() async {
    try {
      final acked = await ref.read(ackRewardsControllerProvider.notifier).ack();
      if (!mounted) return;
      showAppSnackBar(
        context,
        acked > 0 ? '$acked개의 보상을 확인했어요' : '확인할 보상이 없어요',
      );
    } on Object {
      if (!mounted) return;
      showAppSnackBar(context, '보상 확인에 실패했어요', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rewardsProvider);
    final acking = ref.watch(ackRewardsControllerProvider).isLoading;
    // 목록이 비어 있으면 확인할 것이 없다 → 액션 비활성.
    final hasItems = async.asData?.value.items.isNotEmpty ?? false;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('보상함'),
          actions: [
            TextButton(
              onPressed: (acking || !hasItems) ? null : _ackAll,
              child: acking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('모두 확인'),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: SafeArea(
          child: async.when(
            loading: () => const LoadingView(message: '보상을 불러오는 중...'),
            error: (e, _) => ErrorView(
              message: '보상을 불러오지 못했어요',
              onRetry: () => ref.invalidate(rewardsProvider),
            ),
            data: (state) {
              if (state.items.isEmpty) {
                return const EmptyStateView(
                  icon: Icons.card_giftcard_outlined,
                  message: '확인할 보상이 없어요',
                );
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.read(rewardsProvider.notifier).refresh(),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: state.items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == state.items.length) {
                      return _LoadingFooter(visible: state.isLoadingMore);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _RewardTile(reward: state.items[i]),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 보상 1건 카드 — 아이콘 + 종류/대사 + 코인 적립.
class _RewardTile extends StatelessWidget {
  const _RewardTile({required this.reward});

  final Reward reward;

  @override
  Widget build(BuildContext context) {
    final meta = _RewardKind.of(reward.eventType);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(meta.icon, color: AppColors.warning, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (reward.line != null && reward.line!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    reward.line!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkAlt,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (reward.coinDelta > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 2),
                Text(
                  '+${reward.coinDelta}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 이벤트 종류별 라벨·아이콘.
class _RewardKind {
  const _RewardKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static _RewardKind of(String eventType) {
    switch (eventType) {
      case 'DIARY_CONFIRM':
        return const _RewardKind('오늘의 기록', Icons.edit_note);
      case 'RESOLUTION_SUCCESS':
        return const _RewardKind('작심삼일 완주', Icons.emoji_events);
      case 'RESOLUTION_DAY':
        return const _RewardKind('작심삼일 달성', Icons.check_circle_outline);
      case 'STREAK':
        return const _RewardKind('연속 기록', Icons.local_fire_department);
      case 'ATTENDANCE':
        return const _RewardKind('출석', Icons.waving_hand_outlined);
      default:
        return const _RewardKind('보상', Icons.card_giftcard_outlined);
    }
  }
}

/// 페이지 하단 추가 로딩 인디케이터(더 불러오는 중일 때만).
class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(height: AppSpacing.lg);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
