import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/resolution.dart';
import 'providers/resolution_providers.dart';
import 'widgets/resolution_calendar_view.dart';
import 'widgets/resolution_list_tile.dart';

/// 작심삼일 탭 화면.
///
/// 상단 헤더 + 상태 세그먼트(진행중/성공/실패) + 목록/캘린더 토글로 구성한다.
/// 목록은 [resolutionListProvider](선택 상태), 캘린더는 [resolutionCalendarProvider]
/// (표시 월)을 watch한다. 빈/로딩/에러는 shared 위젯을 재사용한다.
class ResolutionTabPage extends ConsumerStatefulWidget {
  const ResolutionTabPage({super.key});

  @override
  ConsumerState<ResolutionTabPage> createState() => _ResolutionTabPageState();
}

class _ResolutionTabPageState extends ConsumerState<ResolutionTabPage> {
  /// 현재 선택된 상태 필터(세그먼트).
  ResolutionStatus _status = ResolutionStatus.ongoing;

  /// true이면 캘린더, false이면 목록.
  bool _calendarMode = false;

  /// 캘린더 표시 중인 달(1일 기준). 결심은 미래에도 진행되므로 상한 없음.
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);
  }

  /// 'yyyy-MM' (캘린더 provider 인자).
  String get _yearMonth =>
      '${_displayMonth.year.toString().padLeft(4, '0')}-'
      '${_displayMonth.month.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 헤더 ──
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '작심삼일',
                      style: TextStyle(
                        fontFamily: 'PoorStory',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.01 * 26,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '3일 도전으로 습관을 만들어봐요',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // ── 세그먼트 + 목록/캘린더 토글 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatusSegment(
                        selected: _status,
                        onChanged: (s) => setState(() => _status = s),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _ViewToggleButton(
                      calendarMode: _calendarMode,
                      onTap: () =>
                          setState(() => _calendarMode = !_calendarMode),
                    ),
                  ],
                ),
              ),
              // ── 본문 ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: _calendarMode ? _buildCalendar() : _buildList(),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/resolution/new'),
          child: const Icon(Icons.flag_outlined),
        ),
      ),
    );
  }

  // ── 목록 ──────────────────────────────────────────────────────

  Widget _buildList() {
    final async = ref.watch(resolutionListProvider(_status));
    return async.when(
      loading: () => const LoadingView(),
      error: (_, _) => ErrorView(
        message: '목록을 불러오지 못했어요',
        onRetry: () => ref.invalidate(resolutionListProvider(_status)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyStateView(
            icon: Icons.flag_outlined,
            message: '아직 이 상태의 작심삼일이 없어요',
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async =>
              ref.invalidate(resolutionListProvider(_status)),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final item = items[index];
              return ResolutionListTile(
                title: item.title,
                startDate: item.startDate,
                endDate: item.endDate,
                status: item.status,
                streakSeq: item.streakSeq,
                dayStatuses: item.dayStatuses,
                onTap: () => context.push('/resolution/${item.id}'),
              );
            },
          ),
        );
      },
    );
  }

  // ── 캘린더 ────────────────────────────────────────────────────

  Widget _buildCalendar() {
    final async = ref.watch(resolutionCalendarProvider(_yearMonth));
    // 월 이동 chevron·스와이프는 데이터 상태와 무관하게 항상 동작하도록,
    // (날짜 × 결심) 리스트를 날짜 정규화 키 맵으로 변환한다.
    final dayMap = <DateTime, List<ResolutionCalendarDay>>{};
    for (final d in async.asData?.value ?? const <ResolutionCalendarDay>[]) {
      final key = DateTime(d.date.year, d.date.month, d.date.day);
      (dayMap[key] ??= []).add(d);
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < 0) {
          _changeMonth(1);
        } else if (v > 0) {
          _changeMonth(-1);
        }
      },
      child: Column(
        children: [
          Expanded(
            child: ResolutionCalendarView(
              month: _displayMonth,
              dayMap: dayMap,
              onPrevMonth: () => _changeMonth(-1),
              onNextMonth: () => _changeMonth(1),
              onDayTap: (date, items) =>
                  context.push('/resolution/${items.first.resolutionId}'),
            ),
          ),
          // 에러 시 하단에 안내(캘린더 골격은 유지).
          if (async.hasError)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '이 달의 진행 상황을 불러오지 못했어요',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// 상태 세그먼트 — 진행중/성공/실패를 pill 버튼으로 표현한다.
///
/// 선택 pill은 primary 채움 + 흰 글자, 비선택은 투명 + inkMuted 글자.
/// 컨테이너 배경은 primarySoft로 세그먼트 영역을 감싼다.
class _StatusSegment extends StatelessWidget {
  const _StatusSegment({required this.selected, required this.onChanged});

  final ResolutionStatus selected;
  final ValueChanged<ResolutionStatus> onChanged;

  static const List<(ResolutionStatus, String)> _items = [
    (ResolutionStatus.ongoing, '진행중'),
    (ResolutionStatus.success, '성공'),
    (ResolutionStatus.failed, '실패'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          for (final (status, label) in _items)
            Expanded(
              child: _SegmentPill(
                label: label,
                selected: status == selected,
                onTap: () => onChanged(status),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.surface : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// 목록/캘린더 전환 아이콘 버튼.
class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({required this.calendarMode, required this.onTap});

  final bool calendarMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgAlt,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(
            // 현재 목록이면 캘린더로 전환 아이콘, 반대면 목록 아이콘.
            calendarMode ? Icons.view_list_outlined : Icons.calendar_month_outlined,
            color: AppColors.ink,
            size: 22,
          ),
        ),
      ),
    );
  }
}
