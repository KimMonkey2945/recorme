import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// 공개범위 코드(PRIVATE/FRIENDS/PUBLIC) → 라벨·아이콘·설명 매핑(단일 진실원).
/// 에디터 세그먼트·상세 변경 시트·공유 버튼에서 공용으로 참조한다.
class VisibilityAssets {
  VisibilityAssets._();

  static const List<String> codes = ['PRIVATE', 'FRIENDS', 'PUBLIC'];

  static String labelOf(String code) => switch (code) {
        'FRIENDS' => '친구 공개',
        'PUBLIC' => '전체 공개',
        _ => '나만 보기',
      };

  static IconData iconOf(String code) => switch (code) {
        'FRIENDS' => Icons.people_outline,
        'PUBLIC' => Icons.public,
        _ => Icons.lock_outline,
      };

  static String descriptionOf(String code) => switch (code) {
        'FRIENDS' => '친구에게만 보여요',
        'PUBLIC' => '피드에서 누구나 볼 수 있어요',
        _ => '나만 볼 수 있어요',
      };
}

/// 에디터용 공개범위 3분기 칩 선택. AppColors.primary(조작 맥락) 색을 쓴다(감정색 accent 아님).
class VisibilitySegment extends StatelessWidget {
  const VisibilitySegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '공개범위',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final code in VisibilityAssets.codes) ...[
              _chip(code),
              if (code != VisibilityAssets.codes.last)
                const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ],
    );
  }

  Widget _chip(String code) {
    final selected = value == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(code),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.bgAlt,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                VisibilityAssets.iconOf(code),
                size: 18,
                color: selected ? AppColors.surface : AppColors.inkAlt,
              ),
              const SizedBox(height: 2),
              Text(
                VisibilityAssets.labelOf(code),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.surface : AppColors.inkAlt,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
