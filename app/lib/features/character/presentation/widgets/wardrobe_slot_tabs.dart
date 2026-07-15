import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// 옷장 슬롯 정의(표시 순서 = 이 목록 순서).
///
/// 코드는 서버 슬롯 문자열 그대로 쓰고, 라벨만 한국어로 바꾼다.
const wardrobeSlots = [
  (code: 'HAT', label: '모자'),
  (code: 'GLASSES', label: '안경'),
  (code: 'OUTFIT', label: '상의'),
  (code: 'BOTTOM', label: '하의'),
  (code: 'SHOES', label: '신발'),
  (code: 'PROP', label: '소품'),
  (code: 'ROOM_PROP', label: '방 꾸미기'),
  (code: 'BACKGROUND', label: '배경'),
];

/// 옷장 상단의 슬롯 선택 탭(가로 스크롤 ChoiceChip 행).
class WardrobeSlotTabs extends StatelessWidget {
  const WardrobeSlotTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// 현재 선택된 슬롯 코드('HAT' 등).
  final String selected;

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Row(
        children: [
          for (final slot in wardrobeSlots)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                key: ValueKey('wardrobe-slot-${slot.code}'),
                label: Text(slot.label),
                selected: slot.code == selected,
                onSelected: (_) => onSelected(slot.code),
                selectedColor: AppColors.primarySoft,
                labelStyle: TextStyle(
                  color: slot.code == selected
                      ? AppColors.primary
                      : AppColors.inkAlt,
                ),
                side: BorderSide(
                  color: slot.code == selected
                      ? AppColors.primary
                      : AppColors.hairline,
                ),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }
}
