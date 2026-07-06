import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import 'providers/friend_providers.dart';
import 'widgets/friend_request_tile.dart';

/// 친구 요청함(/friends/requests). 받은/보낸 요청을 세그먼트로 전환한다.
class FriendRequestsPage extends ConsumerStatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  ConsumerState<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends ConsumerState<FriendRequestsPage> {
  bool _incoming = true;

  Future<void> _run(Future<void> Function() action, String successMsg) async {
    try {
      await action();
      // 요청/친구 목록 상태 갱신.
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(outgoingRequestsProvider);
      ref.invalidate(friendsProvider);
      if (mounted) showAppSnackBar(context, successMsg);
    } on Failure catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('친구 요청'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: _Segment(
                  incoming: _incoming,
                  onChanged: (v) => setState(() => _incoming = v),
                ),
              ),
              Expanded(child: _incoming ? _buildIncoming() : _buildOutgoing()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncoming() {
    final async = ref.watch(incomingRequestsProvider);
    final repo = ref.read(friendRepositoryProvider);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: '요청을 불러오지 못했어요',
        onRetry: () => ref.invalidate(incomingRequestsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyStateView(
            icon: Icons.mail_outline,
            message: '받은 요청이 없어요',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            final r = items[i];
            return FriendRequestTile(
              nickname: r.nickname,
              profileImageUrl: r.profileImageUrl,
              incoming: true,
              onAccept: () =>
                  _run(() => repo.accept(r.requestId), '친구가 되었어요'),
              onReject: () =>
                  _run(() => repo.reject(r.requestId), '요청을 거절했어요'),
            );
          },
        );
      },
    );
  }

  Widget _buildOutgoing() {
    final async = ref.watch(outgoingRequestsProvider);
    final repo = ref.read(friendRepositoryProvider);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: '요청을 불러오지 못했어요',
        onRetry: () => ref.invalidate(outgoingRequestsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyStateView(
            icon: Icons.outgoing_mail,
            message: '보낸 요청이 없어요',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            final r = items[i];
            return FriendRequestTile(
              nickname: r.nickname,
              profileImageUrl: r.profileImageUrl,
              incoming: false,
              // 보낸 요청 취소 = 관계 행 삭제(상대 uuid 기준).
              onCancel: () =>
                  _run(() => repo.remove(r.userUuid), '요청을 취소했어요'),
            );
          },
        );
      },
    );
  }
}

/// 받은/보낸 2분기 세그먼트(pill).
class _Segment extends StatelessWidget {
  const _Segment({required this.incoming, required this.onChanged});

  final bool incoming;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          _pill('받은 요청', incoming, () => onChanged(true)),
          _pill('보낸 요청', !incoming, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.ink : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
