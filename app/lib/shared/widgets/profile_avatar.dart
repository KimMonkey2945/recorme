import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 원형 프로필 아바타. 등록 이미지가 있으면 표시하고, 없거나 로딩/실패 시
/// 닉네임 이니셜(없으면 사람 아이콘)로 폴백한다.
///
/// 앱바(작은 radius)와 프로필 화면(큰 radius) 양쪽에서 재사용한다.
/// [imageUrl]은 화면에서 바로 쓸 수 있는 절대 URL이어야 한다(상대경로 변환은 호출부에서 수행).
/// 비즈니스 로직은 없으며 [onTap] 콜백으로만 동작을 노출한다.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.imageUrl,
    required this.radius,
    this.initial,
    this.onTap,
  });

  /// 표시할 절대 이미지 URL. null이면 이니셜/아이콘 폴백.
  final String? imageUrl;

  /// 원 반지름(px). 앱바 16, 프로필 화면 48 등.
  final double radius;

  /// 폴백 이니셜(1글자). null/빈 값이면 사람 아이콘으로 폴백.
  final String? initial;

  /// 탭 동작. null이면 비대화형(장식용).
  final VoidCallback? onTap;

  /// 닉네임에서 표시용 이니셜 1글자를 추출한다(grapheme 단위, 없으면 null).
  static String? initialOf(String? nickname) {
    final trimmed = nickname?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final body = SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFallback(),
            if (imageUrl != null && imageUrl!.isNotEmpty) _buildNetworkImage(),
          ],
        ),
      ),
    );

    if (onTap == null) return body;
    return Semantics(
      label: '프로필',
      button: true,
      child: GestureDetector(onTap: onTap, child: body),
    );
  }

  /// 항상 깔리는 폴백 레이어(이니셜 또는 아이콘).
  Widget _buildFallback() {
    final hasInitial = initial != null && initial!.isNotEmpty;
    return ColoredBox(
      color: AppColors.primarySoft,
      child: Center(
        child: hasInitial
            ? Text(
                initial!.toUpperCase(),
                style: TextStyle(
                  fontSize: radius * 0.7,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  height: 1.0,
                ),
              )
            : Icon(
                Icons.person_rounded,
                size: radius * 0.9,
                color: AppColors.primary,
              ),
      ),
    );
  }

  /// 폴백 위에 얹히는 네트워크 이미지. 로딩/에러 시 투명 처리해 아래 폴백을 노출.
  Widget _buildNetworkImage() {
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      // 프레임 도착 전에는 비워 폴백 레이어가 보이게 한다.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return const SizedBox.shrink();
      },
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}
