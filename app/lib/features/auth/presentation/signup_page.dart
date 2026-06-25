import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'providers/auth_provider.dart';
import 'widgets/auth_form_fields.dart';

/// 이메일 회원가입 화면. 닉네임/이메일/비밀번호/비밀번호 확인을 입력받는다.
///
/// 제출 성공 시:
///  - Confirm email이 켜져 있으면(session==null) `/signup/confirm`으로 이동해
///    확인 메일 안내를 보여준다.
///  - 즉시 세션이 생기는 경우(미사용 가정)에는 라우터 가드가 메인으로 보낸다.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    try {
      final needsConfirm =
          await ref.read(emailAuthControllerProvider.notifier).submitSignUp(
                email: email,
                password: _passwordController.text,
                nickname: _nicknameController.text.trim(),
              );
      if (!mounted) return;
      if (needsConfirm) {
        // 확인 메일 안내 화면으로 이메일 전달.
        context.go('/signup/confirm', extra: email);
      }
      // needsConfirm이 false면 세션이 즉시 생겨 가드가 메인으로 이동시킨다.
    } on Failure catch (f) {
      if (!mounted) return;
      showAppSnackBar(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(emailAuthControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthTextField(
                    controller: _nicknameController,
                    label: '닉네임',
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    validator: AuthValidators.nickname,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    controller: _emailController,
                    label: '이메일',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    validator: AuthValidators.email,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    controller: _passwordController,
                    label: '비밀번호',
                    hintText: '6자 이상',
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    validator: AuthValidators.password,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    controller: _confirmController,
                    label: '비밀번호 확인',
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
                        : const Text('가입하기'),
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
