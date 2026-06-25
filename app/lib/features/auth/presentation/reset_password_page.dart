import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'providers/auth_provider.dart';
import 'widgets/auth_form_fields.dart';

/// 비밀번호 재설정 화면. 복구 세션 상태에서 새 비밀번호를 입력받는다.
///
/// 메일 링크 진입 시 `AuthChangeEvent.passwordRecovery`로 복구 플래그가 켜지고
/// 라우터가 이 화면으로 유도한다. 저장 성공 시 복구 플래그가 꺼지며 메인으로 이동한다.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    try {
      await ref
          .read(emailAuthControllerProvider.notifier)
          .updatePassword(_passwordController.text);
      if (!mounted) return;
      showAppSnackBar(context, '비밀번호를 변경했어요.');
      // 복구 플래그가 해제됐고 세션이 인증 상태이므로 메인으로 이동.
      context.go('/');
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
          title: const Text('비밀번호 재설정'),
          automaticallyImplyLeading: false,
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
                    '새 비밀번호를 입력해주세요.',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthTextField(
                    controller: _passwordController,
                    label: '새 비밀번호',
                    hintText: '6자 이상',
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    validator: AuthValidators.password,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    controller: _confirmController,
                    label: '새 비밀번호 확인',
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    enabled: !loading,
                    validator: (v) => AuthValidators.confirmPassword(
                      v,
                      _passwordController.text,
                    ),
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
                        : const Text('비밀번호 변경'),
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
