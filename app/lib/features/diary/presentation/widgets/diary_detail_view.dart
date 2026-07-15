import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/emotion_labels.dart';
import '../../../../core/theme/emotion_palette.dart';
import '../../domain/diary_content.dart';
import 'diary_image_embed_builder.dart';
import 'diary_quill_styles.dart';

/// 분석 진행 중 보조 문구(감정 분석 flag on일 때만 노출).
const String kAnalysisEtaText = '곧 이 날의 감정이 기록에 담길 거예요';

/// 기록 상세 표현 위젯(Task 025 — 감정 시각 연출 제거본).
///
/// 감정 LLM 분석을 끈 뒤 감정은 **사용자 직접 입력** 메타데이터가 됐다. 예전의 시네마틱 인트로·
/// 마스코트 영상·러닝 로딩 영상·동적 배경 테마는 전부 제거하고, 읽기 전용 본문 + 상태 배지 +
/// (있으면) 감정 칩만 남긴다. 확정 즉시 DONE이므로 분석 폴링도 없다.
/// (확정 후 캐릭터 리액션 연출은 Task 032에서 이 빈 자리에 들어온다.)
///
/// | analysisStatus | 배지/카드 |
/// |---|---|
/// | DRAFT   | '임시 저장' 카드 |
/// | PENDING | '감정을 담는 중' 카드(감정 분석 flag on일 때만 도달) |
/// | DONE    | 없음(감정 칩만) |
/// | FAILED  | '분석 실패' 배지 |
///
/// [onEdit]이 null이면 수정 버튼을 숨긴다(확정 기록).
class DiaryDetailView extends StatefulWidget {
  const DiaryDetailView({
    super.key,
    required this.dateText,
    required this.content,
    required this.analysisStatus,
    required this.onDelete,
    this.onEdit,
    this.primaryEmotion,
    this.emotionLabel,
  });

  /// 표시할 날짜 문자열 (예: '2026년 6월 24일 (화)').
  final String dateText;

  /// 본문(Quill Delta JSON 문자열. 레거시 plain text도 tolerant 처리).
  final String content;

  /// 상태 — 'DRAFT' / 'PENDING' / 'DONE' / 'FAILED'.
  final String analysisStatus;

  /// 수정 버튼 탭 콜백. null이면 수정 버튼을 숨긴다(확정 기록).
  final VoidCallback? onEdit;

  /// 삭제 버튼 탭 콜백 — 확인 다이얼로그는 호출 페이지가 처리.
  final VoidCallback onDelete;

  /// 사용자 프리셋 감정 코드(예: 'JOY'). 감정 칩 표시용. 없으면 null.
  final String? primaryEmotion;

  /// 사용자 커스텀 감정 라벨(자유 텍스트). 감정 칩 표시용. 없으면 null.
  final String? emotionLabel;

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
    final status = widget.analysisStatus;
    final isPending = status == 'PENDING';
    final hasEmotion =
        (widget.primaryEmotion != null && widget.primaryEmotion!.isNotEmpty) ||
            (widget.emotionLabel != null && widget.emotionLabel!.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 날짜 헤더 ──────────────────────────────────────────
          _DiaryHeader(dateText: widget.dateText),

          // ── 상태 배지 (DRAFT/FAILED만) ─────────────────────────
          if (status == 'DRAFT' || status == 'FAILED')
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _AnalysisStatusBadge(status: status),
            ),

          // ── 감정 칩 (프리셋/커스텀, 있을 때만) ─────────────────
          if (hasEmotion) ...[
            const SizedBox(height: AppSpacing.sm),
            _EmotionChip(
              primaryEmotion: widget.primaryEmotion,
              emotionLabel: widget.emotionLabel,
            ),
          ],

          // ── PENDING: 분석 중 카드(감정 분석 flag on일 때만) ────
          if (isPending) ...[
            const SizedBox(height: AppSpacing.md),
            const _AnalysisPendingCard(),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ── 읽기 전용 리치 본문 ────────────────────────────────
          Expanded(
            child: QuillEditor.basic(
              controller: _controller,
              config: QuillEditorConfig(
                padding: EdgeInsets.zero,
                showCursor: false,
                embedBuilders: const [DiaryImageEmbedBuilder()],
                customStyles: diaryPaperStyles(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── 하단 액션 버튼 ─────────────────────────────────────
          _ActionButtons(onEdit: widget.onEdit, onDelete: widget.onDelete),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 감정 칩 (프리셋 코드 또는 커스텀 라벨)
// ──────────────────────────────────────────────────────────────

/// 사용자 감정을 표시하는 작은 칩. 프리셋이면 이모지+라벨과 감정 색, 커스텀이면 라벨+중립 색.
class _EmotionChip extends StatelessWidget {
  const _EmotionChip({this.primaryEmotion, this.emotionLabel});

  final String? primaryEmotion;
  final String? emotionLabel;

  @override
  Widget build(BuildContext context) {
    final isPreset = primaryEmotion != null && primaryEmotion!.isNotEmpty;
    final color = EmotionPalette.chipColor(
      code: primaryEmotion,
      label: emotionLabel,
    );
    final emoji = isPreset ? emotionEmojiOf(primaryEmotion) : null;
    final text = isPreset ? emotionLabelOf(primaryEmotion) : (emotionLabel ?? '');
    final label = emoji != null ? '$emoji $text' : text;

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
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 날짜 헤더
// ──────────────────────────────────────────────────────────────

/// 상세 화면 상단의 날짜 헤더.
///
/// '2026년 6월 24일 (화)' 포맷의 [dateText]를 파싱해
/// 연/월(inkAlt 14px) + 일(PoorStory 36px) + 요일(inkAlt 600 20px)로 표시한다.
class _DiaryHeader extends StatelessWidget {
  const _DiaryHeader({required this.dateText});

  final String dateText;

  /// '2026년 6월 24일 (화)' → { yearMonth: '2026년 6월', day: '24일', weekday: '화요일' }
  _DateParts _parse(String text) {
    final parts = text.trim().split(' ');
    if (parts.length >= 4) {
      final yearMonth = '${parts[0]} ${parts[1]}';
      final day = parts[2];
      final wkChar = parts[3].replaceAll('(', '').replaceAll(')', '');
      return _DateParts(yearMonth: yearMonth, day: day, weekday: '$wkChar요일');
    }
    return _DateParts(yearMonth: text, day: '', weekday: '');
  }

  @override
  Widget build(BuildContext context) {
    final p = _parse(dateText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p.yearMonth.isNotEmpty)
          Text(
            p.yearMonth,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.inkAlt,
            ),
          ),
        if (p.day.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            p.day,
            style: const TextStyle(
              fontFamily: 'PoorStory',
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.36,
              height: 1.0,
            ),
          ),
        ],
        if (p.weekday.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            p.weekday,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.inkAlt,
            ),
          ),
        ],
      ],
    );
  }
}

/// [_DiaryHeader] 파싱 결과 DTO
class _DateParts {
  const _DateParts({
    required this.yearMonth,
    required this.day,
    required this.weekday,
  });
  final String yearMonth;
  final String day;
  final String weekday;
}

// ──────────────────────────────────────────────────────────────
// 상태 배지 (DRAFT / FAILED 전용)
// ──────────────────────────────────────────────────────────────

/// DRAFT·FAILED 상태 배지.
///
/// DRAFT: bgAlt 배경 전체 폭 카드 (연필 아이콘 + 제목 + 설명 문구).
/// FAILED: 헤어라인 pill 배지 (에러 아이콘 + '분석 실패').
class _AnalysisStatusBadge extends StatelessWidget {
  const _AnalysisStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == 'DRAFT') return _buildDraftCard(context);
    return _buildFailedBadge(context);
  }

  /// DRAFT — bgAlt 카드: 연필 아이콘 + '임시 저장' + 설명 문구
  Widget _buildDraftCard(BuildContext context) {
    return Semantics(
      label: '임시 저장된 기록입니다',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.bgAlt,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18, color: AppColors.ink),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '임시 저장',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '마저 작성하고 기록을 완성해 보세요',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// FAILED — 헤어라인 pill 배지
  Widget _buildFailedBadge(BuildContext context) {
    return Semantics(
      label: '감정 분석에 실패했습니다',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.hairline,
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
              const Icon(Icons.error_outline, size: 14, color: AppColors.inkMuted),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '분석 실패',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 분석 중 카드 (PENDING — 감정 분석 flag on일 때만 도달)
// ──────────────────────────────────────────────────────────────

/// 감정 분석 진행 상태를 안내하는 카드(회전 반짝이 아이콘 + ETA 문구).
class _AnalysisPendingCard extends StatefulWidget {
  const _AnalysisPendingCard();

  @override
  State<_AnalysisPendingCard> createState() => _AnalysisPendingCardState();
}

class _AnalysisPendingCardState extends State<_AnalysisPendingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RotationTransition(
                turns: _rotationController,
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '감정을 담는 중이에요',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    kAnalysisEtaText,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 하단 액션 버튼
// ──────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    this.onEdit,
    required this.onDelete,
  });

  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  static final BorderRadius _buttonRadius =
      BorderRadius.circular(AppRadius.button);

  @override
  Widget build(BuildContext context) {
    final isDraft = onEdit != null;

    return Row(
      children: [
        // 주 액션 버튼 — DRAFT='이어 쓰기'(solid), 확정='닫기'(outlined)
        Expanded(
          child: isDraft
              ? FilledButton.icon(
                  onPressed: onEdit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('이어 쓰기'),
                )
              : OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size(0, 52),
                    side: const BorderSide(color: AppColors.hairline, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
                  ),
                  child: const Text('닫기'),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // 삭제 — 아이콘 전용 OutlinedButton 52×52dp
        SizedBox(
          width: 52,
          height: 52,
          child: OutlinedButton(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: EdgeInsets.zero,
              side: const BorderSide(color: AppColors.error, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: const Icon(Icons.delete_outline, size: 20),
          ),
        ),
      ],
    );
  }
}
