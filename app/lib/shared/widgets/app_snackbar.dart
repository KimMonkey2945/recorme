import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// 앱 전역 스낵바 표시 함수.
///
/// [ScaffoldMessenger]를 통해 하단에 floating 스낵바를 표시한다.
/// - [isError]가 false(기본값): 기본 ink 배경 (정보/성공 메시지)
/// - [isError]가 true: 에러 색 배경 (오류 알림)
///
/// ```dart
/// // 성공 메시지
/// showAppSnackBar(context, '일기가 저장되었어요');
///
/// // 에러 메시지
/// showAppSnackBar(context, '저장에 실패했어요. 다시 시도해주세요.', isError: true);
/// ```
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  // 이전 스낵바가 있으면 즉시 제거 후 새로 표시
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    _buildSnackBar(context, message, isError: isError),
  );
}

/// 스낵바 위젯을 생성하는 내부 함수.
SnackBar _buildSnackBar(
  BuildContext context,
  String message, {
  required bool isError,
}) {
  final textTheme = Theme.of(context).textTheme;

  // 배경색: 에러면 에러 색, 아니면 ink(어두운 토스트)
  final backgroundColor = isError ? AppColors.error : AppColors.ink;
  final foregroundColor = AppColors.surface;

  // 에러 스낵바에는 아이콘 프리픽스 추가
  final Widget content = isError
      ? Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: foregroundColor,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        )
      : Text(
          message,
          style: textTheme.bodyMedium?.copyWith(
            color: foregroundColor,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );

  return SnackBar(
    content: content,
    backgroundColor: backgroundColor,
    behavior: SnackBarBehavior.floating,
    // 화면 좌우에 약간의 여백
    margin: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.lg,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    // 일반 메시지는 2초, 에러 메시지는 3초 표시
    duration: Duration(seconds: isError ? 3 : 2),
    elevation: 4,
  );
}
