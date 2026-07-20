import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import 'providers/friend_providers.dart';
import 'widgets/friend_list_tile.dart';

/// 친구 목록 화면(/friends). 상단 앱바에서 친구 추가·요청함(받은 요청 배지)으로 진입한다.
class FriendsListPage extends ConsumerWidget {
  const FriendsListPage({super.key});

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref, {
    required String uuid,
    required String nickname,
    required bool block,
  }) async {
    final confirmed = await showConfirmDialog(
      context,
      title: block ? '친구 차단' : '친구 삭제',
      message: block
          ? '$nickname 님을 차단하면 서로의 기록이 보이지 않고 다시 친구가 될 수 없어요.'
          : '$nickname 님을 친구에서 삭제할까요?',
      confirmLabel: block ? '차단' : '삭제',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(friendRepositoryProvider).remove(uuid, block: block);
      ref.invalidate(friendsProvider);
      if (context.mounted) {
        showAppSnackBar(context, block ? '차단했어요' : '친구를 삭제했어요');
      }
    } on Failure catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsProvider);
    final pendingCount = ref.watch(pendingRequestCountProvider);

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('친구'),
          actions: [
            // 피드는 탭에서 빠지면서 여기로 진입한다(친구가 탭으로 승격 — 진입 방향 반전).
            IconButton(
              icon: const Icon(Icons.dynamic_feed_outlined),
              tooltip: '피드',
              onPressed: () => context.push('/feed'),
            ),
            IconButton(
              icon: const Icon(Icons.person_add_alt_outlined),
              tooltip: '친구 추가',
              onPressed: () => context.push('/friends/add'),
            ),
            Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: IconButton(
                icon: const Icon(Icons.mail_outline),
                tooltip: '요청함',
                onPressed: () => context.push('/friends/requests'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: SafeArea(
          child: friendsAsync.when(
            loading: () => const LoadingView(message: '친구 목록을 불러오는 중...'),
            error: (e, _) => ErrorView(
              message: '친구 목록을 불러오지 못했어요',
              onRetry: () => ref.invalidate(friendsProvider),
            ),
            data: (friends) {
              if (friends.isEmpty) {
                return EmptyStateView(
                  icon: Icons.people_outline,
                  message: '아직 친구가 없어요',
                  actionLabel: '친구 추가하기',
                  onAction: () => context.push('/friends/add'),
                );
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(friendsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: friends.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final f = friends[i];
                    return FriendListTile(
                      nickname: f.nickname,
                      profileImageUrl: f.profileImageUrl,
                      // 이름을 누르면 그 친구의 recorme 둘러보기(읽기 전용).
                      // 닉네임은 extra 로 넘겨 앱바 제목을 로딩 없이 즉시 띄운다.
                      onTap: () => context.push(
                        '/friends/browse/${f.userUuid}',
                        extra: f.nickname,
                      ),
                      onRemove: () => _remove(
                        context,
                        ref,
                        uuid: f.userUuid,
                        nickname: f.nickname,
                        block: false,
                      ),
                      onBlock: () => _remove(
                        context,
                        ref,
                        uuid: f.userUuid,
                        nickname: f.nickname,
                        block: true,
                      ),
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
