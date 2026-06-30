import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'providers/auth_provider.dart';

/// 가입 직후 "메일을 확인하세요" 안내 화면.
///
/// Confirm email이 켜져 있으면 가입 시 세션이 생기지 않으므로(미인증),
/// 사용자가 메일의 링크로 인증을 완료한 뒤 로그인하도록 안내한다.
/// 메일을 못 받았을 때를 대비해 재전송 버튼을 제공한다.
class EmailConfirmPage extends ConsumerWidget {
  const EmailConfirmPage({super.key, required this.email});

  /// 안내 대상 이메일(가입/로그인 화면에서 전달). null이면 일반 안내만 표시.
  final String? email;

  Future<void> _resend(BuildContext context, WidgetRef ref) async {
    final target = email;
    if (target == null || target.isEmpty) {
      showAppSnackBar(context, '이메일 정보가 없어요. 다시 로그인해주세요.', isError: true);
      return;
    }
    try {
      await ref.read(emailAuthControllerProvider.notifier).resend(target);
      if (context.mounted) {
        showAppSnackBar(context, '확인 메일을 다시 보냈어요.');
      }
    } on Failure catch (f) {
      if (context.mounted) {
        showAppSnackBar(context, f.message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final loading = ref.watch(emailAuthControllerProvider).isLoading;
    final target = email ?? '';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 3),
                // 안내 아이콘
                Container(
                  width: 92,
                  height: 92,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.card + 8),
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '메일함을 확인해주세요',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  target.isEmpty
                      ? '가입하신 이메일로 인증 링크를 보냈어요.\n인증을 완료한 뒤 로그인해주세요.'
                      : '$target 으로\n인증 링크를 보냈어요. 인증을 완료한 뒤 로그인해주세요.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
                const Spacer(flex: 4),
                FilledButton(
                  onPressed: loading ? null : () => _resend(context, ref),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.surface,
                          ),
                        )
                      : const Text('확인 메일 다시 보내기'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: loading ? null : () => context.go('/login'),
                  child: const Text('로그인 화면으로'),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
