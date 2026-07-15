import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/emotion_labels.dart';
import '../../../core/theme/emotion_palette.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../../shared/widgets/reaction_button.dart';
import '../../diary/domain/diary_content.dart';
import '../../diary/presentation/widgets/diary_image_embed_builder.dart';
import '../../diary/presentation/widgets/diary_quill_styles.dart';
import '../data/dto/feed_dto.dart';
import 'providers/feed_providers.dart';

/// 피드 카드 전문 조회 화면(/feed/diary/:id). 타인 글도 열람 가능(viewer-aware).
/// 편집/삭제 없이 정적으로 표시하며, 본문은 diary 의 읽기 전용 Quill 렌더 유틸을 재사용한다.
class FeedDiaryDetailPage extends ConsumerWidget {
  const FeedDiaryDetailPage({super.key, required this.diaryId});

  final String diaryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(diaryId) ?? -1;
    final async = ref.watch(feedDetailProvider(id));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorView(
            message: '기록을 불러오지 못했어요',
            onRetry: () => ref.invalidate(feedDetailProvider(id)),
          ),
          data: (detail) => _FeedDiaryDetailView(detail: detail),
        ),
      ),
    );
  }
}

/// 피드 전문 표현 위젯. 본문은 읽기 전용 Quill 로 렌더하고, 공감은 로컬 낙관적 상태로 토글한다.
class _FeedDiaryDetailView extends ConsumerStatefulWidget {
  const _FeedDiaryDetailView({required this.detail});

  final FeedDetail detail;

  @override
  ConsumerState<_FeedDiaryDetailView> createState() => _FeedDiaryDetailViewState();
}

class _FeedDiaryDetailViewState extends ConsumerState<_FeedDiaryDetailView> {
  late final QuillController _controller;

  /// 공감 로컬 상태(낙관적 갱신). 초기값은 서버 응답.
  late bool _reacted = widget.detail.reactedByMe;
  late int _count = widget.detail.reactionCount;
  bool _submitting = false;

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _controller = QuillController(
      document: documentFromContent(widget.detail.content),
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 공감 토글(낙관적). 서버 결과로 정확값 반영, 실패 시 롤백. 목록 동기화 위해 feedProvider 무효화.
  Future<void> _toggleReaction() async {
    if (_submitting) return;
    _submitting = true;
    final wasReacted = _reacted;
    setState(() {
      _reacted = !wasReacted;
      _count += wasReacted ? -1 : 1;
    });
    try {
      final repo = ref.read(feedRepositoryProvider);
      final result = wasReacted
          ? await repo.unreact(widget.detail.id)
          : await repo.react(widget.detail.id);
      if (mounted) {
        setState(() {
          _reacted = result.reacted;
          _count = result.reactionCount;
        });
      }
      ref.invalidate(feedProvider); // 피드 목록도 최신화.
    } on Failure catch (e) {
      if (mounted) {
        setState(() {
          _reacted = wasReacted;
          _count += wasReacted ? 1 : -1;
        });
        showAppSnackBar(context, e.message, isError: true);
      }
    } finally {
      _submitting = false;
    }
  }

  String get _dateText {
    final d = widget.detail.writtenDate;
    return '${d.year}년 ${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final hasEmotion = d.primaryEmotion != null && d.primaryEmotion!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 작성자 헤더 ──
          Row(
            children: [
              ProfileAvatar(
                radius: 20,
                imageUrl: ApiConfig.resolveImageUrl(d.authorProfileImageUrl),
                initial: ProfileAvatar.initialOf(d.authorNickname),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.authorNickname,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _dateText,
                      style: const TextStyle(fontSize: 12, color: AppColors.inkAlt),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── AI 제목(감정 분석 flag on일 때만 존재) ──
          if (d.aiTitle != null && d.aiTitle!.isNotEmpty) ...[
            Text(
              d.aiTitle!,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── 감정 칩(프리셋, 있을 때만) ──
          if (hasEmotion) ...[
            _FeedDetailEmotionChip(code: d.primaryEmotion!),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── 본문(읽기 전용 리치 텍스트) ──
          Expanded(
            child: QuillEditor.basic(
              controller: _controller,
              config: QuillEditorConfig(
                showCursor: false,
                embedBuilders: const [DiaryImageEmbedBuilder()],
                customStyles: diaryPaperStyles(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── 공감 버튼(낙관적 토글) ──
          ReactionButton(
            reacted: _reacted,
            count: _count,
            accentColor: EmotionPalette.accentOf(d.primaryEmotion),
            size: ReactionButtonSize.large,
            onTap: _toggleReaction,
          ),
        ],
      ),
    );
  }
}

/// 피드 전문의 감정 칩 — 프리셋 이모지 + 라벨(감정 색 테두리).
class _FeedDetailEmotionChip extends StatelessWidget {
  const _FeedDetailEmotionChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final color = EmotionPalette.accentOf(code);
    final emoji = emotionEmojiOf(code);
    final label = emotionLabelOf(code);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color),
      ),
      child: Text(
        emoji != null ? '$emoji $label' : label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
