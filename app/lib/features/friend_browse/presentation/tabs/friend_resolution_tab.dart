import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_view.dart';
import '../../../resolution/domain/resolution.dart';
import '../../../resolution/presentation/widgets/resolution_list_tile.dart';
import '../providers/friend_browse_providers.dart';

/// 둘러보기 — 친구의 작심삼일(읽기 전용).
///
/// 내 작심삼일 탭과 달리 **생성 FAB이 없고, 타일을 눌러도 상세로 가지 않는다**
/// (`onTap`을 넘기지 않는다 — 상세 화면에는 오늘 체크·연장·취소 같은 쓰기 액션이 있다).
/// 진행중/성공/실패 필터만 유지해 "이 친구가 얼마나 해냈나"를 볼 수 있게 한다.
class FriendResolutionTab extends ConsumerStatefulWidget {
  const FriendResolutionTab({super.key, required this.userUuid});

  final String userUuid;

  @override
  ConsumerState<FriendResolutionTab> createState() =>
      _FriendResolutionTabState();
}

class _FriendResolutionTabState extends ConsumerState<FriendResolutionTab> {
  ResolutionStatus? _status;

  static const _filters = <({String label, ResolutionStatus? status})>[
    (label: '전체', status: null),
    (label: '진행중', status: ResolutionStatus.ongoing),
    (label: '성공', status: ResolutionStatus.success),
    (label: '실패', status: ResolutionStatus.failed),
  ];

  @override
  Widget build(BuildContext context) {
    final key = (uuid: widget.userUuid, status: _status);
    final async = ref.watch(friendResolutionListProvider(key));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            children: _filters.map((f) {
              return ChoiceChip(
                label: Text(f.label),
                selected: _status == f.status,
                onSelected: (_) => setState(() => _status = f.status),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const LoadingView(message: '작심삼일을 불러오는 중...'),
            error: (e, _) => ErrorView(
              message: '작심삼일을 불러오지 못했어요',
              onRetry: () => ref.invalidate(friendResolutionListProvider(key)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyStateView(
                  icon: Icons.flag_outlined,
                  message: '아직 도전한 작심삼일이 없어요',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, i) {
                  final r = items[i];
                  return ResolutionListTile(
                    title: r.title,
                    startDate: r.startDate,
                    endDate: r.endDate,
                    status: r.status,
                    streakSeq: r.streakSeq,
                    dayStatuses: r.dayStatuses,
                    // onTap 미전달 — 상세(쓰기 가능)로 진입시키지 않는다.
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
