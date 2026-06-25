import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../auth/presentation/widgets/auth_form_fields.dart';
import '../data/dto/update_profile_request.dart';
import 'providers/profile_providers.dart';

/// 프로필 수정 화면. 닉네임(필수)/프로필 이미지 URL/자기소개(최대 300자)를 편집한다.
///
/// 현재 프로필([myProfileProvider]) 값으로 입력을 프리필하고, 저장 성공 시
/// 조회 캐시를 무효화한 뒤 이전 화면으로 돌아간다.
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  /// bio 최대 길이(백엔드 @Size(300)과 일치).
  static const int bioMaxLength = 300;

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    // 조회 캐시에 있는 현재 값으로 프리필(없으면 빈 값).
    final user = ref.read(myProfileProvider).value;
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
    _imageUrlController =
        TextEditingController(text: user?.profileImageUrl ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _imageUrlController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  String? _validateNickname(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '닉네임을 입력해주세요.';
    if (v.length > 50) return '닉네임은 최대 50자까지 가능해요.';
    return null;
  }

  String? _validateImageUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // 선택 항목
    if (v.length > 2048) return '이미지 URL이 너무 길어요.';
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'http(s)로 시작하는 올바른 URL을 입력해주세요.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final request = UpdateProfileRequest(
      nickname: _nicknameController.text.trim(),
      // 빈 문자열도 전송 → 백엔드가 빈값을 null로 정규화(지우기 허용).
      profileImageUrl: _imageUrlController.text.trim(),
      bio: _bioController.text.trim(),
    );

    try {
      await ref.read(profileEditControllerProvider.notifier).submit(request);
      if (!mounted) return;
      // 조회 캐시 무효화 → 프로필 화면이 최신값으로 다시 로드된다.
      ref.invalidate(myProfileProvider);
      showAppSnackBar(context, '프로필을 저장했어요.');
      context.pop();
    } on Failure catch (f) {
      if (!mounted) return;
      showAppSnackBar(context, f.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(profileEditControllerProvider).isLoading;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('프로필 수정'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
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
                    validator: _validateNickname,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    controller: _imageUrlController,
                    label: '프로필 이미지 URL (선택)',
                    hintText: 'https://...',
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    validator: _validateImageUrl,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // 자기소개: 멀티라인 + 300자 제한
                  TextFormField(
                    controller: _bioController,
                    enabled: !loading,
                    maxLines: 5,
                    maxLength: ProfileEditPage.bioMaxLength,
                    decoration: InputDecoration(
                      labelText: '자기소개 (선택)',
                      hintText: '최대 ${ProfileEditPage.bioMaxLength}자',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide:
                            const BorderSide(color: AppColors.hairline, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide:
                            const BorderSide(color: AppColors.hairline, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide:
                            const BorderSide(color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                        : const Text('저장'),
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
