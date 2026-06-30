import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// 데이터가 없을 때 표시하는 빈 상태(Empty State) 뷰.
///
/// 아이콘, 메시지, 선택적 액션 버튼으로 구성된다.
/// 색상·타이포는 [AppColors]와 [Theme.of(context)]를 통해 참조한다.
///
/// ```dart
/// EmptyStateView(
///   icon: Icons.book_outlined,
///   message: '아직 작성한 일기가 없어요',
///   actionLabel: '첫 일기 쓰기',
///   onAction: () { /* TODO: 로직 연결 지점 */ },
/// )
/// ```
class EmptyStateView extends StatelessWidget {
  /// 상태를 표현하는 아이콘
  final IconData icon;

  /// 사용자에게 보여줄 빈 상태 메시지
  final String message;

  /// 액션 버튼 레이블 (null이면 버튼 숨김)
  final String? actionLabel;

  /// 액션 버튼 탭 콜백 (null이면 버튼 숨김)
  ///
  /// TODO: 로직 연결 지점 — 실제 네비게이션·동작은 호출부에서 주입
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 아이콘 — 64px bgAlt 원 컨테이너 (시안 기준)
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.bgAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── 메시지 — 600 16px inkAlt (시안 기준)
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.inkAlt,
              ),
              textAlign: TextAlign.center,
            ),

            // ── 액션 버튼 (선택적) ──
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton(
                // TODO: 로직 연결 지점 — onAction은 호출부에서 주입
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
