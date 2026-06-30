import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/api_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../auth/presentation/widgets/auth_form_fields.dart';
import '../data/dto/update_profile_request.dart';
import 'providers/profile_providers.dart';
import 'widgets/profile_edit_image_section.dart';

/// 프로필 수정 화면. 닉네임(필수)/자기소개(최대 300자)를 편집하고, 상단에서 프로필 사진을 바꾼다.
///
/// 현재 프로필([myProfileProvider]) 값으로 입력을 프리필한다. 닉네임/자기소개는 "저장"으로
/// 한 번에 반영하고, 프로필 사진은 "사진 변경" 시 즉시 업로드(별도 경로)된다.
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
  late final TextEditingController _bioController;

  /// 방금 선택한 이미지 바이트(미리보기용). 업로드 성공 시 유지, 실패 시 원복.
  Uint8List? _pickedBytes;

  /// 아바타 업로드 진행 여부(닉네임/자기소개 저장 로딩과 별개).
  bool _isImageUploading = false;

  /// 갤러리 피커가 열려 있는 동안 true. 피커 대기 중 버튼 재탭으로 인한 중복 진입 방지.
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    // 조회 캐시에 있는 현재 값으로 프리필(없으면 빈 값).
    final user = ref.read(myProfileProvider).value;
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  String? _validateNickname(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '닉네임을 입력해주세요.';
    if (v.length > 50) return '닉네임은 최대 50자까지 가능해요.';
    return null;
  }

  /// 갤러리에서 이미지를 골라 즉시 업로드한다(닉네임/자기소개 저장과 분리).
  Future<void> _onPickImage() async {
    if (_isPicking || _isImageUploading) return; // 피커 열림 중 재탭 등 중복 진입 방지
    setState(() => _isPicking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return; // 사용자가 선택 취소
      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() {
        _pickedBytes = bytes; // 미리보기 즉시 반영
        _isImageUploading = true;
      });

      try {
        await ref
            .read(profileRepositoryProvider)
            .uploadAvatar(bytes, picked.name);
        if (!mounted) return;
        // 조회 캐시 무효화 → 앱바·프로필 화면이 새 이미지로 갱신.
        ref.invalidate(myProfileProvider);
        showAppSnackBar(context, '프로필 사진을 변경했어요.');
      } on Failure catch (f) {
        if (!mounted) return;
        setState(() => _pickedBytes = null); // 실패 시 미리보기 원복
        showAppSnackBar(context, f.message, isError: true);
      } catch (_) {
        // DioException(네트워크·타임아웃·4xx/5xx)·기타 예외도 안내 + 미리보기 원복.
        // (업로드는 컨트롤러를 경유하지 않는 직접 호출이라 Failure 외 예외가 올라올 수 있음)
        if (!mounted) return;
        setState(() => _pickedBytes = null);
        showAppSnackBar(
          context,
          '사진 업로드 중 문제가 발생했어요. 잠시 후 다시 시도해주세요.',
          isError: true,
        );
      } finally {
        if (mounted) setState(() => _isImageUploading = false);
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final request = UpdateProfileRequest(
      nickname: _nicknameController.text.trim(),
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
    final user = ref.watch(myProfileProvider).value;

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
                  // 프로필 사진(선택 즉시 업로드)
                  Center(
                    child: ProfileEditImageSection(
                      currentImageUrl:
                          ApiConfig.resolveImageUrl(user?.profileImageUrl),
                      localImageBytes: _pickedBytes,
                      initial: ProfileAvatar.initialOf(user?.nickname),
                      isUploading: _isImageUploading,
                      onPickImage: _onPickImage,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthTextField(
                    controller: _nicknameController,
                    label: '닉네임',
                    textInputAction: TextInputAction.next,
                    enabled: !loading,
                    validator: _validateNickname,
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
                            const BorderSide(color: AppColors.primary, width: 1.5),
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
