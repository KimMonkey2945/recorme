import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/resolution.dart';

/// 결심 상태 배지 — 진행중/성공/실패를 색상 pill로 표현한다.
///
/// 감정 전용 accent(바이올렛)는 쓰지 않는다. 상태색 규칙:
/// - ongoing → primary / primarySoft, '진행중'
/// - success → success / successSoft, '성공'
/// - failed  → error / errorSoft, '실패'
/// - unknown → inkMuted / bgAlt(안전 폴백), '진행중' 취급
class ResolutionStatusBadge extends StatelessWidget {
  const ResolutionStatusBadge({super.key, required this.status});

  final ResolutionStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String label) = switch (status) {
      ResolutionStatus.ongoing => (AppColors.primary, AppColors.primarySoft, '진행중'),
      ResolutionStatus.success => (AppColors.success, AppColors.successSoft, '성공'),
      ResolutionStatus.failed => (AppColors.error, AppColors.errorSoft, '실패'),
      ResolutionStatus.unknown => (AppColors.inkMuted, AppColors.bgAlt, '진행중'),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
