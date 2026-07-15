import 'package:flutter/material.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/emotion_labels.dart';
import '../../../../core/theme/emotion_palette.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../../shared/widgets/reaction_button.dart';
import '../../data/dto/feed_dto.dart';

/// 피드 카드(Task 025 — 감정 동적 배경 제거).
///
/// 감정 연출을 걷어낸 뒤 카드는 **중립 배경(surface + hairline)**으로 통일하고,
/// 감정은 우상단 **감정 칩**(프리셋 이모지+라벨)으로만 표시한다. 작성자 헤더 + 감정 칩 +
/// AI 제목(있으면) + 본문 미리보기(3줄) + 공감 버튼으로 구성한다.
class FeedDiaryCard extends StatelessWidget {
  const FeedDiaryCard({
    super.key,
    required this.item,
    this.onTap,
    this.onReactionTap,
  });

  final FeedItem item;
  final VoidCallback? onTap;

  /// 공감 버튼 탭(호출부가 낙관적 갱신+서버 호출 처리).
  final VoidCallback? onReactionTap;

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String get _dateText {
    final d = item.writtenDate;
    return '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context) {
    final hasEmotion =
        item.primaryEmotion != null && item.primaryEmotion!.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 작성자 헤더 + 감정 칩 ──
                Row(
                  children: [
                    ProfileAvatar(
                      radius: 18,
                      imageUrl: ApiConfig.resolveImageUrl(item.authorProfileImageUrl),
                      initial: ProfileAvatar.initialOf(item.authorNickname),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.authorNickname,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _dateText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasEmotion) _FeedEmotionChip(code: item.primaryEmotion!),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── AI 제목(감정 분석 flag on일 때만 존재) ──
                if (item.aiTitle != null && item.aiTitle!.isNotEmpty) ...[
                  Text(
                    item.aiTitle!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],

                // ── 본문 미리보기(3줄) ──
                Text(
                  item.preview ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.ink,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── 공감 버튼 + 이동 화살표 ──
                Row(
                  children: [
                    ReactionButton(
                      reacted: item.reactedByMe,
                      count: item.reactionCount,
                      accentColor: EmotionPalette.accentOf(item.primaryEmotion),
                      onTap: onReactionTap,
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.inkMuted.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 피드 카드 우상단 감정 칩 — 프리셋 이모지 + 라벨(감정 색 테두리).
class _FeedEmotionChip extends StatelessWidget {
  const _FeedEmotionChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final color = EmotionPalette.accentOf(code);
    final emoji = emotionEmojiOf(code);
    final label = emotionLabelOf(code);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color),
      ),
      child: Text(
        emoji != null ? '$emoji $label' : label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
