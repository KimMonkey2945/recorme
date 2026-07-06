import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/profile_avatar.dart';

/// 친구 요청 한 줄. [incoming]=true 면 받은 요청(수락/거절 버튼),
/// false 면 보낸 요청('대기중' + 취소 버튼). 동작은 콜백으로만 노출.
class FriendRequestTile extends StatelessWidget {
  const FriendRequestTile({
    super.key,
    required this.nickname,
    this.profileImageUrl,
    required this.incoming,
    this.onAccept,
    this.onReject,
    this.onCancel,
  });

  final String nickname;
  final String? profileImageUrl;
  final bool incoming;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorderRadius,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            ProfileAvatar(
              radius: 22,
              imageUrl: profileImageUrl,
              initial: ProfileAvatar.initialOf(nickname),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                nickname,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (incoming) ..._incomingActions() else ..._outgoingActions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _incomingActions() => [
        OutlinedButton(
          onPressed: onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.inkMuted,
            side: const BorderSide(color: AppColors.hairline),
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          child: const Text('거절'),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: onAccept,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.surface,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          child: const Text('수락'),
        ),
      ];

  List<Widget> _outgoingActions() => [
        const Text('대기중', style: TextStyle(color: AppColors.inkMuted)),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.hairline),
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          child: const Text('취소'),
        ),
      ];
}
