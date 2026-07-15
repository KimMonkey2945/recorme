import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// 옷장 하단의 저장 바 — 로컬 변경(dirty)이 있을 때만 슬라이드 인.
///
/// 탭은 미리보기만 바꾸고, 서버 커밋은 이 바의 "저장"이 담당한다
/// (배치 교체 API 특성상 시행착오 중 오조작 커밋을 막는 설계).
class WardrobeSaveBar extends StatelessWidget {
  const WardrobeSaveBar({
    super.key,
    required this.visible,
    required this.saving,
    required this.onSave,
    required this.onDiscard,
  });

  /// 로컬 변경 여부(false면 바가 내려가 있다).
  final bool visible;

  /// 저장 요청 진행 중 여부(버튼 비활성 + 스피너).
  final bool saving;

  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '변경사항이 있어요',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.inkAlt),
              ),
            ),
            TextButton(
              onPressed: saving ? null : onDiscard,
              child: const Text('취소'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              key: const ValueKey('wardrobe-save'),
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
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
    );
  }
}
