import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/resolution.dart';

// ─────────────────────────────────────────────────────────────
// 파일 내부 상수 (calendar_month_view 복제)
// ─────────────────────────────────────────────────────────────

const List<String> _kWeekdays = ['일', '월', '화', '수', '목', '금', '토'];
const Color _kSundayLabelColor = AppColors.error;
const Color _kSaturdayLabelColor = AppColors.primary;
const double _kDayCellBgSize = 36.0;
const double _kMarkerAreaHeight = 12.0;
const double _kDayCellHeight = 60.0;
const double _kDayCellMaxHeight = 100.0;

// ─────────────────────────────────────────────────────────────
// 날짜 계산 유틸
// ─────────────────────────────────────────────────────────────

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

int _firstWeekdayOffset(DateTime month) =>
    DateTime(month.year, month.month, 1).weekday % 7;

/// 체크 상태 → 셀 도트 색상. DONE=success, MISSED=error, 그 외=hairline.
Color _markerColor(CheckStatus status) {
  switch (status) {
    case CheckStatus.done:
      return AppColors.success;
    case CheckStatus.missed:
      return AppColors.error;
    case CheckStatus.pending:
    case CheckStatus.unknown:
      return AppColors.hairline;
  }
}

// ─────────────────────────────────────────────────────────────
// ResolutionCalendarView (공개 위젯)
// ─────────────────────────────────────────────────────────────

/// 작심삼일 월별 캘린더 표현 위젯.
///
/// diary의 [CalendarMonthView]를 복제하되, (날짜 × 결심)당 1행인
/// [ResolutionCalendarDay] 리스트를 마커로 받아 날짜 아래 상태 도트를 찍는다.
/// 결심은 미래에도 진행되므로 다음 달 이동을 항상 허용한다(미래 달 상한 없음).
class ResolutionCalendarView extends StatelessWidget {
  const ResolutionCalendarView({
    super.key,
    required this.month,
    required this.dayMap,
    required this.onDayTap,
    this.onPrevMonth,
    this.onNextMonth,
  });

  /// 표시할 달(1일 기준). 연·월만 의미를 가진다.
  final DateTime month;

  /// 날짜(시간=0 정규화) → 그 날짜의 결심 마커 리스트.
  final Map<DateTime, List<ResolutionCalendarDay>> dayMap;

  /// 날짜 셀 탭 콜백(그 날짜의 마커 리스트를 함께 전달).
  final void Function(DateTime date, List<ResolutionCalendarDay> items) onDayTap;

  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthHeader(
          month: month,
          onPrevMonth: onPrevMonth,
          onNextMonth: onNextMonth,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _WeekdayRow(),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: _DateGrid(month: month, dayMap: dayMap, onDayTap: onDayTap),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _MonthHeader
// ─────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    this.onPrevMonth,
    this.onNextMonth,
  });

  final DateTime month;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.2,
              ),
              children: [
                TextSpan(text: '${month.year}년 '),
                TextSpan(
                  text: '${month.month}월',
                  style: const TextStyle(color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '이전 달',
          onPressed: onPrevMonth,
          icon: const Icon(Icons.chevron_left),
          color: AppColors.ink,
        ),
        IconButton(
          tooltip: '다음 달',
          onPressed: onNextMonth,
          icon: const Icon(Icons.chevron_right),
          color: AppColors.ink,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _WeekdayRow
// ─────────────────────────────────────────────────────────────

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_kWeekdays.length, (index) {
        final Color color = switch (index) {
          0 => _kSundayLabelColor,
          6 => _kSaturdayLabelColor,
          _ => AppColors.inkMuted,
        };
        return Expanded(
          child: Center(
            child: Text(
              _kWeekdays[index],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _DateGrid
// ─────────────────────────────────────────────────────────────

class _DateGrid extends StatelessWidget {
  const _DateGrid({
    required this.month,
    required this.dayMap,
    required this.onDayTap,
  });

  final DateTime month;
  final Map<DateTime, List<ResolutionCalendarDay>> dayMap;
  final void Function(DateTime date, List<ResolutionCalendarDay> items) onDayTap;

  @override
  Widget build(BuildContext context) {
    final int offset = _firstWeekdayOffset(month);
    final int daysCount = _daysInMonth(month);
    final int totalCells = ((offset + daysCount) / 7).ceil() * 7;
    final int rows = totalCells ~/ 7;

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double rowHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight / rows)
                .clamp(_kDayCellHeight, _kDayCellMaxHeight)
            : _kDayCellHeight;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: rowHeight,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            final int dayNumber = index - offset + 1;
            if (dayNumber < 1 || dayNumber > daysCount) {
              return const SizedBox.shrink();
            }
            final DateTime date = DateTime(month.year, month.month, dayNumber);
            final int weekdayIndex = index % 7;
            final items = dayMap[date] ?? const <ResolutionCalendarDay>[];

            return _DayCell(
              day: dayNumber,
              isToday: _isSameDay(date, today),
              items: items,
              weekdayIndex: weekdayIndex,
              onTap: items.isEmpty ? null : () => onDayTap(date, items),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _DayCell
// ─────────────────────────────────────────────────────────────

/// 캘린더 날짜 셀. 오늘은 primary 채운 원, 그 외는 숫자만. 하단에 결심 마커 도트.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.items,
    required this.weekdayIndex,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final List<ResolutionCalendarDay> items;
  final int weekdayIndex;
  final VoidCallback? onTap;

  Color _dayTextColor() {
    if (isToday) return AppColors.surface;
    if (weekdayIndex == 0) return AppColors.error;
    if (weekdayIndex == 6) return AppColors.primary;
    return AppColors.ink;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: _kDayCellBgSize,
            height: _kDayCellBgSize,
            decoration: isToday
                ? const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  )
                : null,
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 16,
                color: _dayTextColor(),
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // 결심 마커 도트(최대 3개, 초과분은 표시 생략).
          SizedBox(
            height: _kMarkerAreaHeight,
            child: items.isEmpty
                ? null
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final item in items.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _markerColor(item.checkStatus),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
