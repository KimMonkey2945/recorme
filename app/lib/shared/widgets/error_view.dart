import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// 오류 발생 시 표시하는 에러 뷰.
///
/// 에러 아이콘, 오류 메시지, 선택적 "다시 시도" 버튼을 포함한다.
/// [onRetry]가 null이면 재시도 버튼을 숨긴다.
///
/// ```dart
/// ErrorView(
///   message: '데이터를 불러오지 못했어요',
///   onRetry: () { /* TODO: 로직 연결 지점 */ },
/// )
/// ```
class ErrorView extends StatelessWidget {
  /// 사용자에게 보여줄 오류 메시지
  final String message;

  /// 재시도 콜백 (null이면 재시도 버튼 숨김)
  ///
  /// TODO: 로직 연결 지점 — 실제 재시도 로직은 호출부에서 주입
  final VoidCallback? onRetry;

  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 에러 아이콘 컨테이너 ──
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── 오류 메시지 ──
            Text(
              message,
              style: textTheme.bodyLarge?.copyWith(
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
            ),

            // ── 재시도 버튼 (선택적) ──
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                // TODO: 로직 연결 지점 — onRetry는 호출부에서 주입
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 시도'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.surface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
