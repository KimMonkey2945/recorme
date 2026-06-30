import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/diary_content.dart';
import 'diary_image_embed_builder.dart';
import 'diary_quill_styles.dart';

/// 분석 진행 중 보조 문구(상수로 분리해 향후 일괄 수정 용이).
const String kAnalysisEtaText = '곧 이 날의 감정이 기록에 담길 거예요';

/// 기록 상세 표현 위젯.
///
/// ## 배경 전략
/// 감정 배경색([backgroundColor])은 이 위젯이 아닌 **호출 측 Container**에서
/// AnimatedContainer로 적용한다. 이 위젯은 내부 콘텐츠(헤더·본문·버튼)만 담당.
///
/// ## 상태별 UI
/// | analysisStatus | 배지 | 헤더 추가 | 분석중 카드 |
/// |---|---|---|---|
/// | DRAFT   | '임시 저장' 배지 | 없음 | 없음 |
/// | PENDING | 없음 | 없음 | 표시 |
/// | DONE    | 없음 | 이모지·코멘트·제목 | 없음 |
/// | FAILED  | '분석 실패' 배지 | 없음 | 없음 |
///
/// [onEdit]이 null이면 수정 버튼을 숨긴다 — 확정 기록(analysisStatus != 'DRAFT')에서
/// 호출 측이 null로 전달한다.
class DiaryDetailView extends StatefulWidget {
  const DiaryDetailView({
    super.key,
    required this.dateText,
    required this.content,
    required this.analysisStatus,
    required this.onDelete,
    this.onEdit,
    this.pollingTimedOut = false,
    // 감정 테마 필드 (DONE 시에만 비-null)
    this.moodCardColor,
    this.textColor,
    this.accentColor,
    this.moodEmoji,
    this.aiComment,
    this.aiTitle,
  });

  /// 표시할 날짜 문자열 (예: '2026년 6월 24일 (화)').
  final String dateText;

  /// 본문(Quill Delta JSON 문자열. 레거시 plain text도 tolerant 처리).
  final String content;

  /// LLM 분석 상태 — 'DRAFT' / 'PENDING' / 'DONE' / 'FAILED'.
  final String analysisStatus;

  /// 수정 버튼 탭 콜백. null이면 수정 버튼을 숨긴다(확정 기록).
  final VoidCallback? onEdit;

  /// 삭제 버튼 탭 콜백 — 확인 다이얼로그는 호출 페이지가 처리.
  final VoidCallback onDelete;

  /// 폴링 타임아웃 여부. true이면 "잠시 후 다시 확인해 주세요" 안내로 전환.
  final bool pollingTimedOut;

  /// 무드 카드 채움색 — 감정 배경색(파스텔). DONE 시에만 비-null. 페이지 배경엔 쓰지 않음.
  final Color? moodCardColor;

  /// 감정 기반 텍스트 색(없으면 기본 잉크 색 사용).
  final Color? textColor;

  /// 감정 기반 강조색(이모지 칩·코멘트 색조 등에 활용).
  final Color? accentColor;

  /// AI 분석 무드 이모지 (예: "😊"). DONE 시 날짜 헤더에 표시.
  final String? moodEmoji;

  /// AI 생성 한 줄 코멘트. DONE 시 날짜 헤더 우측에 표시.
  final String? aiComment;

  /// AI 생성 제목. DONE 시 날짜 아래 보조 라인에 표시.
  final String? aiTitle;

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
    final isPending = widget.analysisStatus == 'PENDING';
    final isDone = widget.analysisStatus == 'DONE';
    // 무드 카드 표시 여부 — DONE이고 이모지/코멘트/제목 중 하나라도 있을 때.
    final showMoodCard = isDone &&
        (widget.moodEmoji != null ||
            widget.aiComment != null ||
            widget.aiTitle != null);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 날짜 라인 ──────────────────────────────────────────
          _DiaryHeader(dateText: widget.dateText),

          // ── 상태 배지 (DRAFT/FAILED만 표시, PENDING/DONE은 숨김) ─
          _buildStatusBadge(),

          // ── PENDING: 분석 중 카드 ─────────────────────────────
          if (isPending) ...[
            const SizedBox(height: AppSpacing.md),
            _AnalysisPendingCard(timedOut: widget.pollingTimedOut),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ── 읽기 전용 리치 본문 ──────────────────────────────
          Expanded(
            child: QuillEditor.basic(
              controller: _controller,
              config: QuillEditorConfig(
                padding: EdgeInsets.zero,
                showCursor: false,
                embedBuilders: const [DiaryImageEmbedBuilder()],
                // 종이 + 명조(serif) 본문 — 감정 텍스트색(있으면) 반영.
                customStyles: diaryPaperStyles(context, color: widget.textColor),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── 무드 카드 (DONE, 삭제 버튼 바로 위) ─────────────────
          if (showMoodCard) ...[
            _MoodCard(
              moodEmoji: widget.moodEmoji,
              aiComment: widget.aiComment,
              aiTitle: widget.aiTitle,
              cardColor: widget.moodCardColor ?? AppColors.accentSoft,
              inkColor: widget.textColor ?? AppColors.ink,
              accentColor: widget.accentColor ?? AppColors.accent,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── 하단 액션 버튼 ──────────────────────────────────
          _ActionButtons(onEdit: widget.onEdit, onDelete: widget.onDelete),
        ],
      ),
    );
  }

  /// DRAFT / FAILED일 때만 상태 배지를 반환한다.
  /// PENDING은 큰 카드가 대신하고, DONE은 헤더 이모지·코멘트가 대신한다.
  Widget _buildStatusBadge() {
    final status = widget.analysisStatus;
    if (status == 'PENDING' || status == 'DONE') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: _AnalysisStatusBadge(status: status),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 날짜 + AI 헤더
// ──────────────────────────────────────────────────────────────

/// 상세 화면 상단의 날짜 헤더.
///
/// '2026년 6월 24일 (화)' 포맷의 [dateText]를 파싱해
/// 연/월(inkAlt 14px) + 일(WantedSans 800 36px) + 요일(inkAlt 600 20px)로
/// 계층형으로 표시한다.
class _DiaryHeader extends StatelessWidget {
  const _DiaryHeader({required this.dateText});

  final String dateText;

  /// '2026년 6월 24일 (화)' → { yearMonth: '2026년 6월', day: '24일', weekday: '화요일' }
  _DateParts _parse(String text) {
    final parts = text.trim().split(' ');
    if (parts.length >= 4) {
      final yearMonth = '${parts[0]} ${parts[1]}';
      final day = parts[2];
      // '(화)' → '화요일'
      final wkChar = parts[3].replaceAll('(', '').replaceAll(')', '');
      return _DateParts(
        yearMonth: yearMonth,
        day: day,
        weekday: '$wkChar요일',
      );
    }
    // 폴백: 그대로 표시
    return _DateParts(yearMonth: text, day: '', weekday: '');
  }

  @override
  Widget build(BuildContext context) {
    final p = _parse(dateText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 연/월 — inkAlt 14px 500
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
          // 일 — PoorStory 36px
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
          // 요일 — inkAlt 600 20px
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
// 무드 카드 (DONE 기록의 감정 표현 — 이모지·제목·코멘트 묶음)
// ──────────────────────────────────────────────────────────────

/// 감정색으로 채운 둥근 카드. 좌측 강조 바 + 큰 이모지 칩 + AI 제목/코멘트.
class _MoodCard extends StatelessWidget {
  const _MoodCard({
    required this.cardColor,
    required this.inkColor,
    required this.accentColor,
    this.moodEmoji,
    this.aiComment,
    this.aiTitle,
  });

  final Color cardColor;
  final Color inkColor;
  final Color accentColor;
  final String? moodEmoji;
  final String? aiComment;
  final String? aiTitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
        // 좌측 강조 바 — 감정 accent.
        border: Border(
          left: BorderSide(color: accentColor, width: 4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 큰 이모지 칩
            if (moodEmoji != null)
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  moodEmoji!,
                  style: const TextStyle(fontSize: 34),
                ),
              ),
            if (moodEmoji != null) const SizedBox(width: AppSpacing.md),

            // AI 제목 + 코멘트
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (aiTitle != null)
                    Text(
                      aiTitle!,
                      style: textTheme.titleMedium?.copyWith(
                        color: inkColor,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  if (aiTitle != null && aiComment != null)
                    const SizedBox(height: AppSpacing.xs),
                  if (aiComment != null)
                    Text(
                      aiComment!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: inkColor,
                        height: 1.45,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 4,
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
// 상태 배지 (DRAFT / FAILED 전용)
// ──────────────────────────────────────────────────────────────

/// DRAFT·FAILED 상태 배지.
///
/// DRAFT: bgAlt 배경 전체 폭 카드 (연필 아이콘 + 제목 + 설명 문구).
/// FAILED: 헤어라인 pill 배지 (에러 아이콘 + '분석 실패').
/// PENDING·DONE은 각각 큰 카드·헤더가 대신하므로 이 위젯에서 제외.
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

  /// FAILED — 기존 헤어라인 pill 배지 유지
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
// 분석 중 카드 (PENDING일 때 본문 위에 표시)
// ──────────────────────────────────────────────────────────────

/// 감정 분석 진행 상태를 안내하는 카드.
///
/// [timedOut]이 false이면 회전하는 반짝이 아이콘(Icons.auto_awesome) + ETA 문구,
/// true이면 시계 아이콘 + "잠시 후 다시 확인해 주세요"로 전환된다.
class _AnalysisPendingCard extends StatefulWidget {
  const _AnalysisPendingCard({this.timedOut = false});

  final bool timedOut;

  @override
  State<_AnalysisPendingCard> createState() => _AnalysisPendingCardState();
}

class _AnalysisPendingCardState extends State<_AnalysisPendingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // 2초에 1회전 무한 반복 — 분석 진행 중 시각 피드백
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
            // 아이콘: 진행 중=회전 반짝이, 타임아웃=시계
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: widget.timedOut
                  ? const Icon(
                      Icons.schedule_outlined,
                      color: AppColors.accent,
                      size: 20,
                    )
                  : RotationTransition(
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
                    widget.timedOut ? '잠시 후 다시 확인해 주세요' : '감정을 담는 중이에요',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!widget.timedOut) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      kAnalysisEtaText,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '이 화면을 벗어나도 분석은 계속돼요',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ],
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

/// 하단 액션 버튼 영역.
///
/// DRAFT([onEdit] != null):
///   [이어 쓰기 (FilledButton, 확장)] + [휴지통 아이콘 OutlinedButton 52px]
///
/// 확정([onEdit] == null):
///   [닫기 (OutlinedButton, 확장)] + [휴지통 아이콘 OutlinedButton 52px]
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
                  // TODO: 로직 연결 지점 — Navigator.of(context).pop() 처리
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
