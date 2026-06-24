import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// 확인/취소 다이얼로그를 표시하고 사용자의 선택을 반환한다.
///
/// - 확인 버튼 탭: `true` 반환
/// - 취소 버튼 탭 또는 배경 탭으로 dismiss: `false` 반환
/// - [isDestructive]가 true이면 확인 버튼이 에러 색(빨간 계열)으로 표시된다.
///
/// ```dart
/// final confirmed = await showConfirmDialog(
///   context,
///   title: '일기 삭제',
///   message: '이 일기를 삭제하면 되돌릴 수 없어요. 계속할까요?',
///   confirmLabel: '삭제',
///   isDestructive: true,
/// );
/// if (confirmed) { /* TODO: 로직 연결 지점 */ }
/// ```
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '확인',
  String cancelLabel = '취소',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
    ),
  );
  // 배경 탭으로 dismiss된 경우 null → false로 처리
  return result ?? false;
}

/// [showConfirmDialog]의 실제 다이얼로그 위젯.
/// 내부용(private) StatelessWidget으로 분리해 const 생성자를 활용한다.
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDestructive,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // 확인 버튼 색상: 파괴적 액션이면 에러 색, 아니면 accent
    final confirmColor =
        isDestructive ? colorScheme.error : AppColors.accent;
    final confirmForeground = AppColors.surface;

    return AlertDialog(
      // 좌우 패딩 조정 — 기본값보다 넉넉하게
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),

      // ── 제목 ──
      title: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),

      // ── 본문 메시지 ──
      content: Text(
        message,
        style: textTheme.bodyMedium?.copyWith(
          color: AppColors.ink,
          height: 1.5,
        ),
      ),

      // ── 액션 버튼 ──
      actions: [
        // 취소 버튼
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.inkMuted,
            side: const BorderSide(color: AppColors.hairline),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: Text(cancelLabel),
        ),
        const SizedBox(width: AppSpacing.sm),

        // 확인 버튼 (파괴적이면 에러 색 적용)
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: confirmForeground,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
