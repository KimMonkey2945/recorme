import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'providers/auth_provider.dart';
import 'widgets/auth_form_fields.dart';

/// 비밀번호 찾기 화면. 이메일을 입력받아 재설정 메일을 보낸다.
///
/// (이메일이 곧 아이디이므로 "아이디 찾기"는 제공하지 않는다.)
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    try {
      await ref
          .read(emailAuthControllerProvider.notifier)
          .requestPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      showAppSnackBar(context, '비밀번호 재설정 메일을 보냈어요. 메일함을 확인해주세요.');
      context.pop();
    } on Failure catch (f) {
      if (!mounted) return;
      showAppSnackBar(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final loading = ref.watch(emailAuthControllerProvider).isLoading;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('비밀번호 찾기'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '가입한 이메일을 입력하시면\n비밀번호 재설정 링크를 보내드려요.',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthTextField(
                    controller: _emailController,
                    label: '이메일',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    enabled: !loading,
                    validator: AuthValidators.email,
                    onFieldSubmitted: (_) => loading ? null : _submit(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: loading ? null : _submit,
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
                        : const Text('재설정 메일 보내기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
