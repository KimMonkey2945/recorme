import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/resolution.dart';
import 'providers/resolution_providers.dart';
import 'widgets/resolution_status_badge.dart';
import 'widgets/resolution_step_row.dart';

const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 작심삼일 상세 화면.
///
/// [resolutionByIdProvider]로 단건을 조회해 제목·기간·상태·3일 스텝·진행률을 보여준다.
/// 오늘 차례가 PENDING이면 '오늘 완료' 버튼, 성공이면 '3일 더 연장하기', 실패면
/// '다시 시작하기'를 제공한다. AppBar에서 삭제(취소)할 수 있다.
/// 완료/연장 성공 후 관련 provider invalidate는 T7 컨트롤러가 처리한다.
class ResolutionDetailPage extends ConsumerWidget {
  const ResolutionDetailPage({super.key, required this.id});

  final int id;

  String _shortDate(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  /// 체크 상태 + 오늘 날짜로부터 3일 스텝의 시각 상태를 계산한다.
  List<ResolutionStepState> _stepStates(Resolution r) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return r.checks.map((c) {
      switch (c.status) {
        case CheckStatus.done:
          return ResolutionStepState.done;
        case CheckStatus.missed:
          return ResolutionStepState.missed;
        case CheckStatus.pending:
        case CheckStatus.unknown:
          final d = DateTime(c.checkDate.year, c.checkDate.month, c.checkDate.day);
          if (d.isAtSameMomentAs(today)) return ResolutionStepState.today;
          if (d.isAfter(today)) return ResolutionStepState.future;
          // 지난 날인데 아직 pending이면 놓친 것으로 표시.
          return ResolutionStepState.missed;
      }
    }).toList();
  }

  /// 오늘 차례 체크가 PENDING인지(오늘 완료 버튼 노출 조건).
  bool _canCompleteToday(Resolution r) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return r.checks.any((c) {
      final d = DateTime(c.checkDate.year, c.checkDate.month, c.checkDate.day);
      return c.status == CheckStatus.pending && d.isAtSameMomentAs(today);
    });
  }

  /// 상태별 강조색(진행률 바·헤더).
  Color _statusColor(ResolutionStatus status) => switch (status) {
        ResolutionStatus.success => AppColors.success,
        ResolutionStatus.failed => AppColors.error,
        ResolutionStatus.ongoing => AppColors.primary,
        ResolutionStatus.unknown => AppColors.primary,
      };

  // ── 액션 ──────────────────────────────────────────────────────

  Future<void> _completeToday(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(completeTodayControllerProvider.notifier).submit(id);
      if (!context.mounted) return;
      showAppSnackBar(context, '오늘 완료 체크했어요');
    } on Failure catch (f) {
      if (!context.mounted) return;
      showAppSnackBar(context, f.message, isError: true);
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, '완료 체크에 실패했어요', isError: true);
    }
  }

  Future<void> _extend(BuildContext context, WidgetRef ref) async {
    try {
      final next =
          await ref.read(extendControllerProvider.notifier).submit(id);
      if (!context.mounted) return;
      showAppSnackBar(context, '3일 더 이어가요');
      // 새로 생성된 다음 3일 상세로 교체 이동.
      context.pushReplacement('/resolution/${next.id}');
    } on Failure catch (f) {
      if (!context.mounted) return;
      showAppSnackBar(context, f.message, isError: true);
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, '연장에 실패했어요', isError: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '작심삼일 삭제',
      message: '이 작심삼일을 삭제할까요? 삭제하면 되돌릴 수 없어요.',
      confirmLabel: '삭제',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(resolutionRepositoryProvider).cancel(id);
      // 목록·캘린더 갱신(취소는 컨트롤러 밖 액션이라 여기서 직접 invalidate).
      ref.invalidate(resolutionListProvider);
      ref.invalidate(resolutionCalendarProvider);
      if (!context.mounted) return;
      showAppSnackBar(context, '삭제했어요');
      context.pop();
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, '삭제에 실패했어요', isError: true);
    }
  }

  // ── 빌드 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(resolutionByIdProvider(id));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorView(
            message: '작심삼일을 불러오지 못했어요',
            onRetry: () => ref.invalidate(resolutionByIdProvider(id)),
          ),
          data: (r) => _DetailBody(
            resolution: r,
            stepStates: _stepStates(r),
            statusColor: _statusColor(r.status),
            shortDate: _shortDate,
            canCompleteToday: _canCompleteToday(r),
            completing:
                ref.watch(completeTodayControllerProvider).isLoading,
            extending: ref.watch(extendControllerProvider).isLoading,
            onCompleteToday: () => _completeToday(context, ref),
            onExtend: () => _extend(context, ref),
            onRestart: () => context.push('/resolution/new'),
          ),
        ),
      ),
    );
  }
}

/// 상세 본문 — 로딩/에러 분기 밖 순수 표현부.
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.resolution,
    required this.stepStates,
    required this.statusColor,
    required this.shortDate,
    required this.canCompleteToday,
    required this.completing,
    required this.extending,
    required this.onCompleteToday,
    required this.onExtend,
    required this.onRestart,
  });

  final Resolution resolution;
  final List<ResolutionStepState> stepStates;
  final Color statusColor;
  final String Function(DateTime) shortDate;
  final bool canCompleteToday;
  final bool completing;
  final bool extending;
  final VoidCallback onCompleteToday;
  final VoidCallback onExtend;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final r = resolution;
    final doneCount =
        r.checks.where((c) => c.status == CheckStatus.done).length;
    final progress = doneCount / 3;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ── 제목 + 상태 배지 ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                r.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ResolutionStatusBadge(status: r.status),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // ── 기간 + 연속 라벨 ──
        Row(
          children: [
            Text(
              '${shortDate(r.startDate)} ~ ${shortDate(r.endDate)}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.inkAlt,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (r.streakSeq >= 2) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '🔥${r.streakSeq}연속',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        // ── 3일 스텝 ──
        ResolutionStepRow(states: stepStates),
        const SizedBox(height: AppSpacing.xl),
        // ── 진행률 바 ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '진행률',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkAlt,
              ),
            ),
            Text(
              '$doneCount / 3일',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: AppColors.hairline,
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // ── 상태별 액션 ──
        ..._buildActions(context),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    // 오늘 완료 버튼(오늘 차례가 PENDING일 때만).
    if (canCompleteToday) {
      return [
        _PrimaryButton(
          label: '오늘 완료하기',
          loading: completing,
          onPressed: onCompleteToday,
        ),
      ];
    }

    // 성공 → 3일 더 연장하기.
    if (resolution.status == ResolutionStatus.success) {
      return [
        _SuccessCard(streakSeq: resolution.streakSeq),
        const SizedBox(height: AppSpacing.lg),
        _PrimaryButton(
          label: '3일 더 연장하기',
          loading: extending,
          onPressed: onExtend,
        ),
      ];
    }

    // 실패 → 다시 시작하기.
    if (resolution.status == ResolutionStatus.failed) {
      return [
        const _FailedCard(),
        const SizedBox(height: AppSpacing.lg),
        _PrimaryButton(
          label: '다시 시작하기',
          loading: false,
          onPressed: onRestart,
        ),
      ];
    }

    // 진행 중이지만 오늘 차례가 없을 때(예: 오늘 이미 완료) — 안내만.
    return [
      const Center(
        child: Text(
          '오늘 몫은 끝났어요. 내일 다시 이어가요!',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.inkAlt,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];
  }
}

/// 조작 CTA 버튼(primary). 로딩 시 스피너.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: AppColors.surface,
                strokeWidth: 2.5,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
    );
  }
}

/// 성공 축하 카드(successSoft).
class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.streakSeq});

  final int streakSeq;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          const Icon(Icons.celebration, color: AppColors.success, size: 32),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '3일 도전 성공!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            streakSeq >= 2
                ? '벌써 $streakSeq번째 3일이에요. 이 기세를 이어가볼까요?'
                : '작은 습관의 첫걸음을 내디뎠어요. 이어가볼까요?',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.inkAlt,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 실패 안내 카드(errorSoft).
class _FailedCard extends StatelessWidget {
  const _FailedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Column(
        children: [
          Icon(Icons.sentiment_dissatisfied_outlined,
              color: AppColors.error, size: 32),
          SizedBox(height: AppSpacing.sm),
          Text(
            '이번엔 아쉽게 놓쳤어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '괜찮아요. 다시 3일부터 가볍게 시작해봐요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.inkAlt,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
