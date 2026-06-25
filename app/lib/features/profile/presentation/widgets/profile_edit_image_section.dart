import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/profile_avatar.dart';

/// 프로필 수정 화면의 이미지 선택 섹션.
///
/// 현재 이미지([currentImageUrl]) 또는 방금 선택한 로컬 바이트([localImageBytes])를
/// 큰 원형으로 미리보고, "사진 변경" 버튼으로 [onPickImage]를 호출한다.
/// 업로드 진행 중([isUploading])이면 오버레이 + 버튼 비활성으로 표시만 하고,
/// 실제 선택/업로드 로직은 콜백으로만 노출한다(이 위젯은 표현 전용).
class ProfileEditImageSection extends StatelessWidget {
  const ProfileEditImageSection({
    super.key,
    this.currentImageUrl,
    this.localImageBytes,
    this.initial,
    this.isUploading = false,
    this.onPickImage,
  });

  /// 서버에 저장된 현재 이미지의 절대 URL(없으면 null).
  final String? currentImageUrl;

  /// 방금 선택한 이미지 바이트(미리보기용, 웹·모바일 공통). 있으면 우선 표시.
  final Uint8List? localImageBytes;

  /// 폴백 이니셜(닉네임 첫 글자).
  final String? initial;

  /// 업로드 진행 표시.
  final bool isUploading;

  /// "사진 변경" 탭 콜백.
  final VoidCallback? onPickImage;

  /// 미리보기 원 지름.
  static const double _diameter = 112;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _diameter,
          height: _diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (localImageBytes != null)
                ClipOval(
                  child: Image.memory(
                    localImageBytes!,
                    width: _diameter,
                    height: _diameter,
                    fit: BoxFit.cover,
                  ),
                )
              else
                ProfileAvatar(
                  imageUrl: currentImageUrl,
                  radius: _diameter / 2,
                  initial: initial,
                ),
              if (isUploading)
                const _UploadingOverlay(diameter: _diameter),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: isUploading ? null : onPickImage,
          icon: const Icon(Icons.camera_alt_rounded, size: 16),
          label: const Text('사진 변경'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
          ),
        ),
      ],
    );
  }
}

/// 업로드 중 원형 반투명 오버레이 + 스피너.
class _UploadingOverlay extends StatelessWidget {
  const _UploadingOverlay({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        // AppColors.ink(0x232228) 40% 알파 — const 유지를 위해 리터럴 사용.
        color: Color(0x66232228),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.surface,
        ),
      ),
    );
  }
}
