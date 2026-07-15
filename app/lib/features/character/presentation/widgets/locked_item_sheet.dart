import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/item_group.dart';

/// 미보유(잠금) 아이템의 해금 조건을 안내하는 바텀시트.
///
/// 옷장에서 잠긴 아이템을 탭하면 이 시트로 "어떻게 얻는지"를 보여준다.
/// - **MISSION**: 어떤 미션을 얼마나(진행률) 달성하면 해금되는지.
/// - **COIN**: 몇 코인으로 살 수 있는지(★ 실제 구매는 다음 단계 — 여기선 안내만).
///
/// 상점 화면 없이 옷장이 해금/구매 노출의 단일 지점이라는 설계를 이 시트가 구현한다.
Future<void> showLockedItemSheet(BuildContext context, ItemGroup item) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modal)),
    ),
    builder: (_) => _LockedItemSheet(item: item),
  );
}

class _LockedItemSheet extends StatelessWidget {
  const _LockedItemSheet({required this.item});

  final ItemGroup item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 그랩 핸들 ──
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // ── 아이템 썸네일 + 이름 ──
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.bgAlt,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    item.thumbnailUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.lock_rounded,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    item.nameKo,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            // ── 해금 조건 ──
            _UnlockGuide(item: item),
          ],
        ),
      ),
    );
  }
}

/// 해금 조건 안내 — MISSION은 진행바, COIN은 가격 + "곧 열려요".
class _UnlockGuide extends StatelessWidget {
  const _UnlockGuide({required this.item});

  final ItemGroup item;

  @override
  Widget build(BuildContext context) {
    final lock = item.lockedBy;
    if (lock != null) {
      final ratio = lock.threshold > 0
          ? (lock.progress / lock.threshold).clamp(0.0, 1.0)
          : 0.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "'${lock.title}'\n미션을 달성하면 해금돼요.",
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: AppColors.hairline,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${lock.progress} / ${lock.threshold}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, color: AppColors.inkAlt),
          ),
        ],
      );
    }

    if (item.acquireType == 'COIN') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on,
                  color: AppColors.warning, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${item.coinPrice}코인으로 해금',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '코인 구매 기능은 곧 열려요.',
            style: TextStyle(fontSize: 14, color: AppColors.inkAlt),
          ),
        ],
      );
    }

    // 폴백 — lockedBy도 없고 COIN도 아닌 미보유(운영상 드묾).
    return const Text(
      '아직 잠긴 아이템이에요.',
      style: TextStyle(fontSize: 15, color: AppColors.inkAlt),
    );
  }
}
