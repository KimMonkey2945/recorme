import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/profile_avatar.dart';

/// 친구 목록 한 줄(카드 셸 + 아바타 + 닉네임 + 더보기 메뉴).
/// 비즈니스 로직 없이 [onTap]·[onRemove] 콜백으로만 동작을 노출한다.
///
/// [onTap]은 그 친구의 recorme 둘러보기 진입용이다. 더보기(PopupMenuButton)는 자체 히트테스트가
/// 우선하므로 카드 전체를 InkWell로 감싸도 삭제·차단 메뉴는 그대로 동작한다.
class FriendListTile extends StatelessWidget {
  const FriendListTile({
    super.key,
    required this.nickname,
    this.profileImageUrl,
    this.onTap,
    this.onRemove,
    this.onBlock,
  });

  final String nickname;
  final String? profileImageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardBorderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardBorderRadius,
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardBorderRadius,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            ProfileAvatar(
              radius: 24,
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.inkMuted),
              tooltip: '더보기',
              onSelected: (value) {
                if (value == 'remove') onRemove?.call();
                if (value == 'block') onBlock?.call();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'remove', child: Text('친구 삭제')),
                PopupMenuItem(value: 'block', child: Text('차단')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
