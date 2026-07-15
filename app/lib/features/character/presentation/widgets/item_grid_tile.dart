import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/item_group.dart';

/// 옷장 그리드의 아이템 타일 1칸.
///
/// 상태 표현:
/// - **선택(로컬 미리보기 착용)**: primary 2px 테두리 + 우상단 체크 배지.
/// - **보유(미착용)**: 기본 카드(hairline 테두리).
/// - **미보유**: 흑백 처리 + 자물쇠. 미션 잠금이면 진행률("7/10")을, 코인이면 가격을 보여준다.
///   탭 자체가 비활성이다(onTap null) — 해금은 미션/상점의 몫이다.
class ItemGridTile extends StatelessWidget {
  const ItemGridTile({
    super.key,
    required this.item,
    required this.selected,
    this.onTap,
  });

  final ItemGroup item;

  /// 로컬 미리보기 기준 착용/진열 여부(서버 커밋 전 상태).
  final bool selected;

  /// 미보유면 null(비활성).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final thumbnail = Image.asset(
      item.thumbnailUrl,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.checkroom_rounded, color: AppColors.inkMuted),
      ),
    );

    return Material(
      color: selected ? AppColors.primarySoft : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        key: ValueKey('item-tile-${item.groupCode}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: item.owned
                          ? thumbnail
                          // 미보유: 흑백(채도 0 행렬) 처리로 잠금 상태를 드러낸다.
                          : ColorFiltered(
                              colorFilter: const ColorFilter.matrix([
                                0.2126, 0.7152, 0.0722, 0, 0, //
                                0.2126, 0.7152, 0.0722, 0, 0, //
                                0.2126, 0.7152, 0.0722, 0, 0, //
                                0, 0, 0, 0.55, 0,
                              ]),
                              child: thumbnail,
                            ),
                    ),
                    if (!item.owned)
                      const Center(
                        child: Icon(
                          Icons.lock_rounded,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    if (selected)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: AppColors.surface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.nameKo,
                style: textTheme.bodySmall?.copyWith(color: AppColors.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (!item.owned)
                Text(
                  _lockCaption(),
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.inkMuted,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 미보유 사유 한 줄: 미션 잠금은 진행률, 코인은 가격, 그 외엔 잠금 표기.
  String _lockCaption() {
    final lock = item.lockedBy;
    if (lock != null) return '미션 ${lock.progress}/${lock.threshold}';
    if (item.acquireType == 'COIN') return '${item.coinPrice}코인';
    return '잠김';
  }
}
