import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/diary_content.dart';
import 'diary_image_embed_builder.dart';

/// 일기 상세 표현 위젯.
///
/// 본문은 [QuillController]를 읽기 전용으로 구성해 서식·인라인 이미지를 렌더한다.
/// Scaffold / AppBar / 그라데이션 배경은 호출 측(DiaryDetailPage)이 처리한다.
class DiaryDetailView extends StatefulWidget {
  const DiaryDetailView({
    super.key,
    required this.dateText,
    required this.content,
    required this.analysisStatus,
    required this.onEdit,
    required this.onDelete,
  });

  /// 표시할 날짜 문자열 (예: '2026년 6월 24일 (화)').
  final String dateText;

  /// 본문(Quill Delta JSON 문자열. 레거시 plain text도 tolerant 처리).
  final String content;

  /// LLM 분석 상태 — 'PENDING' 또는 'DONE'.
  final String analysisStatus;

  /// 수정 버튼 탭 콜백.
  final VoidCallback onEdit;

  /// 삭제 버튼 탭 콜백 — 확인 다이얼로그는 호출 페이지가 처리.
  final VoidCallback onDelete;

  @override
  State<DiaryDetailView> createState() => _DiaryDetailViewState();
}

class _DiaryDetailViewState extends State<DiaryDetailView> {
  late QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _buildReadOnlyController(widget.content);
  }

  @override
  void didUpdateWidget(covariant DiaryDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _controller.dispose();
      _controller = _buildReadOnlyController(widget.content);
    }
  }

  QuillController _buildReadOnlyController(String content) {
    final controller = QuillController(
      document: documentFromContent(content),
      selection: const TextSelection.collapsed(offset: 0),
    );
    controller.readOnly = true;
    return controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateHeader(dateText: widget.dateText),
          const SizedBox(height: AppSpacing.sm),
          _AnalysisStatusBadge(status: widget.analysisStatus),
          const SizedBox(height: AppSpacing.xl),
          // 읽기 전용 리치 본문(인라인 이미지 포함). 스크롤은 에디터 자체가 담당.
          Expanded(
            child: QuillEditor.basic(
              controller: _controller,
              config: const QuillEditorConfig(
                padding: EdgeInsets.zero,
                showCursor: false,
                embedBuilders: [DiaryImageEmbedBuilder()],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _ActionButtons(onEdit: widget.onEdit, onDelete: widget.onDelete),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 날짜 헤더
// ──────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.dateText});

  final String dateText;

  @override
  Widget build(BuildContext context) {
    return Text(
      dateText,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 분석 상태 배지
// ──────────────────────────────────────────────────────────────

/// LLM 분석 진행 상태를 시각화하는 pill 배지.
/// - PENDING: 12 dp 원형 인디케이터 + '분석 중'
/// - DONE   : 체크 아이콘 + '분석 완료'
class _AnalysisStatusBadge extends StatelessWidget {
  const _AnalysisStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final bool isPending = status == 'PENDING';
    final String semanticLabel =
        isPending ? '감정 분석 중입니다' : '감정 분석이 완료되었습니다';
    final TextStyle? labelStyle =
        Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w500,
            );

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPending) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.check_circle,
                  size: 14,
                  color: AppColors.accent,
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              Text(
                isPending ? '분석 중' : '분석 완료',
                style: labelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 하단 액션 버튼
// ──────────────────────────────────────────────────────────────

/// 수정·삭제 두 버튼을 같은 너비로 가로 배치.
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static final BorderRadius _buttonRadius =
      BorderRadius.circular(AppRadius.button);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              minimumSize: const Size(0, 52),
              side: const BorderSide(color: AppColors.hairline, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('수정'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              minimumSize: const Size(0, 52),
              side: const BorderSide(color: AppColors.error, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('삭제'),
          ),
        ),
      ],
    );
  }
}
