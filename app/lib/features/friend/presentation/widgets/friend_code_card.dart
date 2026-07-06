import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_snackbar.dart';

/// 내 친구코드 카드. 코드를 크게 보여주고 복사 버튼을 제공한다.
/// 복사(Clipboard)는 SDK 내장 기능이라 이 위젯 안에서 처리한다.
class FriendCodeCard extends StatelessWidget {
  const FriendCodeCard({super.key, required this.code});

  /// 내 친구코드(8자). null이면 로딩 자리표시.
  final String? code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '내 친구코드',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  code ?? '········',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, color: AppColors.primary),
                tooltip: '복사',
                onPressed: code == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: code!));
                        if (context.mounted) {
                          showAppSnackBar(context, '친구코드를 복사했어요');
                        }
                      },
              ),
            ],
          ),
          const Text(
            '이 코드를 친구에게 공유하면 나를 추가할 수 있어요.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
