import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../data/dto/friend_dto.dart';

/// 친구 검색 결과 한 줄. 우측 trailing이 관계 상태([FriendRelation])에 따라 분기한다:
/// NONE→'추가' 버튼, REQUESTED→'요청됨'(비활성), FRIEND→'친구' 칩, INCOMING→'수락' 버튼, BLOCKED→'차단됨'.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    this.onAdd,
    this.onAccept,
  });

  final FriendSearchResult result;

  /// NONE 상태에서 친구 요청 보내기.
  final VoidCallback? onAdd;

  /// INCOMING 상태에서 상대 요청 수락하기(선택).
  final VoidCallback? onAccept;

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
              imageUrl: result.profileImageUrl,
              initial: ProfileAvatar.initialOf(result.nickname),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                result.nickname,
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
            _trailing(),
          ],
        ),
      ),
    );
  }

  Widget _trailing() {
    switch (result.relation) {
      case FriendRelation.none:
        return FilledButton(
          onPressed: onAdd,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.surface,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          child: const Text('추가'),
        );
      case FriendRelation.incoming:
        return FilledButton(
          onPressed: onAccept,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.surface,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          child: const Text('수락'),
        );
      case FriendRelation.requested:
        return const Text('요청됨', style: TextStyle(color: AppColors.inkMuted));
      case FriendRelation.friend:
        return _chip('친구', AppColors.successSoft, AppColors.success);
      case FriendRelation.blocked:
        return _chip('차단됨', AppColors.errorSoft, AppColors.error);
    }
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.chipBorderRadius),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
        ),
      );
}
