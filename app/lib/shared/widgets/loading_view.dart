import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// 데이터 로딩 중 표시하는 로딩 뷰.
///
/// accent 색상의 [CircularProgressIndicator]를 화면 중앙에 배치한다.
/// 선택적으로 로딩 메시지를 함께 표시할 수 있다.
///
/// ```dart
/// const LoadingView()
/// LoadingView(message: '일기를 불러오는 중...')
/// ```
class LoadingView extends StatelessWidget {
  /// 로딩 중 표시할 메시지 (null이면 메시지 숨김)
  final String? message;

  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 스피너 ──
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 2.5,
              strokeCap: StrokeCap.round,
            ),
          ),

          // ── 선택적 메시지 ──
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.inkMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
