import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_view.dart';
import '../../../character/presentation/widgets/character_stage.dart';
import '../providers/friend_browse_providers.dart';

/// 둘러보기 — 친구의 캐릭터 홈(읽기 전용).
///
/// 내 홈과 달리 **출석 적립·코인/보상 배지·옷장·보상함·이달의 기록이 전부 없다**.
/// 캐릭터 렌더는 [CharacterStage]를 무수정 재사용한다(provider를 watch 하지 않는 순수 위젯이라
/// 남의 캐릭터도 그대로 그려진다 — 착용 아이템 z순 오버레이 포함).
class FriendCharacterTab extends ConsumerWidget {
  const FriendCharacterTab({super.key, required this.userUuid});

  final String userUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(friendCharacterProvider(userUuid));

    return async.when(
      loading: () => const LoadingView(message: '친구의 캐릭터를 불러오는 중...'),
      error: (e, _) => ErrorView(
        message: '캐릭터를 불러오지 못했어요',
        onRetry: () => ref.invalidate(friendCharacterProvider(userUuid)),
      ),
      data: (friend) {
        final character = friend.character;
        if (character == null) {
          // 친구가 아직 온보딩을 끝내지 않은 경우 — 오류가 아니라 빈 상태다.
          return const EmptyStateView(
            icon: Icons.pets_outlined,
            message: '아직 캐릭터를 고르지 않았어요',
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.lg,
            AppSpacing.screenHorizontal,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CharacterStage(
                  assetPath: character.thumbnailUrl,
                  equipment: friend.equipment,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                character.nameKo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
