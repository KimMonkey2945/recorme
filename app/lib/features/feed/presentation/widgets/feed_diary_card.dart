import 'package:flutter/material.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/diary_theme.dart';
import '../../../../shared/widgets/emotion_avatar.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../../shared/widgets/reaction_button.dart';
import '../../data/dto/feed_dto.dart';

/// 피드 감정 카드. 앱 정체성(감정 동적 테마)에 맞춰 카드 배경 전면에 감정 파스텔색을 입힌다.
/// 작성자 헤더 + 무드 아바타 + AI 제목 + 본문 미리보기(3줄) + 공감 버튼으로 구성한다.
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
    final theme = DiaryTheme.fromEmotion(item.primaryEmotion);
    final textColor = theme.textColor;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                // ── 작성자 헤더 ──
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
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _dateText,
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    EmotionAvatar(
                      emotionCode: item.primaryEmotion,
                      size: 32,
                      moodEmoji: item.moodEmoji,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── AI 제목 ──
                if (item.aiTitle != null && item.aiTitle!.isNotEmpty) ...[
                  Text(
                    item.aiTitle!,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],

                // ── 본문 미리보기(3줄) ──
                Text(
                  item.preview ?? '',
                  style: TextStyle(fontSize: 14, height: 1.5, color: textColor),
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
                      accentColor: theme.accentColor,
                      onTap: onReactionTap,
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: textColor.withValues(alpha: 0.4),
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
