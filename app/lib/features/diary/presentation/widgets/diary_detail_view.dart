import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// 일기 상세 표현 위젯.
///
/// 비즈니스 로직을 포함하지 않는 순수 표현 위젯입니다.
/// 모든 데이터는 생성자 파라미터로, 동작은 콜백으로만 노출합니다.
/// Scaffold / AppBar / 그라데이션 배경은 호출 측(DiaryDetailPage)이 처리합니다.
///
/// 사용 예:
/// ```dart
/// DiaryDetailView(
///   dateText: '2026년 6월 24일 (화)',
///   content: diary.content,
///   analysisStatus: diary.analysisStatus,
///   onEdit: () => context.push('/editor/${diary.id}'),
///   onDelete: _showDeleteConfirmDialog,
/// )
/// ```
class DiaryDetailView extends StatelessWidget {
  const DiaryDetailView({
    super.key,
    required this.dateText,
    required this.content,
    required this.analysisStatus,
    required this.onEdit,
    required this.onDelete,
  });

  /// 표시할 날짜 문자열 (예: '2026년 6월 24일 (화)')
  final String dateText;

  /// 일기 전체 본문 내용
  final String content;

  /// LLM 분석 상태 — 'PENDING' 또는 'DONE'
  final String analysisStatus;

  /// 수정 버튼 탭 콜백
  final VoidCallback onEdit;

  /// 삭제 버튼 탭 콜백 — 확인 다이얼로그는 호출 페이지가 처리
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 페이지 그라데이션 위에 콘텐츠 여백 확보
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 헤드라인
          _DateHeader(dateText: dateText),
          const SizedBox(height: AppSpacing.sm),
          // 분석 상태 pill 배지
          _AnalysisStatusBadge(status: analysisStatus),
          const SizedBox(height: AppSpacing.xl),
          // 스크롤 가능한 일기 본문 — Expanded로 남은 공간 모두 사용
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: _ContentText(content: content),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // 수정·삭제 하단 버튼 쌍
          _ActionButtons(onEdit: onEdit, onDelete: onDelete),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 날짜 헤더
// ──────────────────────────────────────────────────────────────

/// 일기 날짜를 헤드라인 스타일로 표시합니다.
///
/// 동적 테마(Phase 4)에서 폰트가 교체될 수 있도록
/// Theme.of(context).textTheme을 통해 스타일을 참조합니다.
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
      // 극단적으로 좁은 화면에서 오버플로우 방지
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 분석 상태 배지
// ──────────────────────────────────────────────────────────────

/// LLM 분석 진행 상태를 시각화하는 pill 형태 배지입니다.
///
/// - PENDING: 12 dp 원형 인디케이터(strokeWidth 2) + '분석 중'
/// - DONE   : 체크 아이콘 + '분석 완료'
///
/// 감정·테마·음악 결과 표시는 이 위젯의 범위 밖입니다(placeholder).
class _AnalysisStatusBadge extends StatelessWidget {
  const _AnalysisStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final bool isPending = status == 'PENDING';

    // 스크린 리더용 시맨틱 레이블
    final String semanticLabel =
        isPending ? '감정 분석 중입니다' : '감정 분석이 완료되었습니다';

    // 배지 텍스트 스타일 — 칩 테마와 일치하는 labelSmall 기반
    final TextStyle? labelStyle =
        Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w500,
            );

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true, // Row 자식 요소 중복 읽기 방지
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          // 토큰: AppRadius.chip = 999 dp (pill 형태)
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, // 12 dp
            vertical: AppSpacing.xs,   //  4 dp
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPending) ...[
                // PENDING 상태: 12 dp 크기의 불확정 원형 인디케이터
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ] else ...[
                // DONE 상태: 완료 체크 아이콘
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
// 본문 텍스트
// ──────────────────────────────────────────────────────────────

/// 일기 본문을 읽기 편한 행간으로 표시합니다.
///
/// 동적 테마에서 폰트/색상이 오버라이드될 수 있도록
/// Theme.of(context).textTheme 기반으로 스타일을 구성합니다.
class _ContentText extends StatelessWidget {
  const _ContentText({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Text(
      content,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.ink,
            // 기본값(1.5)보다 넉넉한 행간으로 긴 일기 본문 가독성 향상
            height: 1.6,
          ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 하단 액션 버튼
// ──────────────────────────────────────────────────────────────

/// 수정·삭제 두 버튼을 같은 너비로 가로 배치합니다.
///
/// 버튼 높이 52 dp — 탭 영역 48 dp 최소 기준 충족.
/// 실제 화면 전환·삭제 처리는 각 콜백을 통해 호출 페이지가 수행합니다.
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  // 버튼 공통 모서리 반경 — 토큰: AppRadius.button = 14 dp
  static final BorderRadius _buttonRadius =
      BorderRadius.circular(AppRadius.button);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 수정 버튼 — hairline 테두리, 중립 색상
        Expanded(
          child: OutlinedButton.icon(
            // TODO: 로직 연결 지점 — 일기 수정 화면으로 이동
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
        // 삭제 버튼 — error 색상 강조, 파괴적 액션임을 시각적으로 구분
        Expanded(
          child: OutlinedButton.icon(
            // TODO: 로직 연결 지점 — 확인 다이얼로그는 호출 페이지가 처리 후 onDelete() 호출
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
