import 'package:flutter/material.dart';

import 'package:record/core/theme/app_colors.dart';
import 'package:record/core/theme/app_spacing.dart';
import 'package:record/features/diary/data/dto/diary_dto.dart';

// ─────────────────────────────────────────────────────────────
// 파일 내부 상수
// ─────────────────────────────────────────────────────────────

/// 요일 레이블 (일요일 시작)
const List<String> _kWeekdays = ['일', '월', '화', '수', '목', '금', '토'];

/// 일요일 레이블 색상 — AppColors.error(적색)
const Color _kSundayLabelColor = AppColors.error;

/// 토요일 레이블 색상 — AppColors.primary(블루)
const Color _kSaturdayLabelColor = AppColors.primary;

/// 날짜 배경 원 크기 (dp)
const double _kDayCellBgSize = 36.0;

/// 날짜 셀 하단 이모지·상태 표시 영역 높이 (dp).
///
/// DONE 기록: 이모지(fontSize 12), DRAFT: 배경 링으로 이미 구분됨(빈 공간).
/// 고정 높이로 셀 크기 일관성을 보장한다.
const double _kEmotionIndicatorHeight = 18.0;

/// 날짜 셀 최소 높이 (dp) — 콘텐츠(원+갭+이모지 영역)를 담는 하한.
/// 실제 행 높이는 [_DateGrid]에서 가용 세로 공간에 맞춰 이 값~[_kDayCellMaxHeight]로 정해진다.
const double _kDayCellHeight = 60.0;

/// 날짜 셀 최대 높이 (dp) — 매우 긴 화면에서 과도하게 늘어지지 않도록 상한.
const double _kDayCellMaxHeight = 100.0;

// ─────────────────────────────────────────────────────────────
// 날짜 계산 유틸 (순수 계산 — 비즈니스 로직 아님)
// ─────────────────────────────────────────────────────────────

/// 연·월·일만 비교하는 날짜 동등 비교
bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 해당 월의 총 일수
int _daysInMonth(DateTime month) =>
    DateTime(month.year, month.month + 1, 0).day;

/// 해당 월 1일의 그리드 열 오프셋 (일요일 시작 기준)
///
/// Dart weekday: 1=월 ~ 7=일.
/// 일요일 시작 캘린더이므로 일(7) → 0, 월(1) → 1, ... 토(6) → 6.
int _firstWeekdayOffset(DateTime month) =>
    DateTime(month.year, month.month, 1).weekday % 7;

// ─────────────────────────────────────────────────────────────
// CalendarMonthView (공개 위젯)
// ─────────────────────────────────────────────────────────────

/// 월별 캘린더 표현 위젯.
///
/// 순수 프레젠테이션 위젯 — 상태·비즈니스 로직 없음.
/// 데이터는 생성자 파라미터, 동작은 콜백으로만 노출.
///
/// [dayMap]에 날짜가 있으면:
/// - DONE: hairline 링 원 + 아래에 accent 5px 점
/// - DRAFT: hairline 링 원 + 아래에 inkMuted 5px 점
/// - 오늘: primary 채운 원(항상 최우선)
///
/// ### MainCalendarPage에서 사용 예
/// ```dart
/// CalendarMonthView(
///   month: DateTime(2026, 6),
///   dayMap: {DateTime(2026, 6, 3): DiarySummaryDay(...)},
///   selectedDate: _selectedDate,
///   onDateTap: (date) { /* 상태 갱신 + 라우팅 */ },
///   onPrevMonth: () { /* 표시 월 감소 */ },
///   onNextMonth: () { /* 표시 월 증가 */ },
/// )
/// ```
class CalendarMonthView extends StatelessWidget {
  const CalendarMonthView({
    super.key,
    required this.month,
    required this.dayMap,
    this.selectedDate,
    required this.onDateTap,
    this.onPrevMonth,
    this.onNextMonth,
  });

  /// 표시할 달(1일 기준). 연·월만 의미를 가진다.
  final DateTime month;

  /// 날짜(시간=0으로 정규화) → 감정 요약 맵.
  /// 포함된 날짜는 상태에 따라 감정색 원·이모지 또는 회색 링으로 구분된다.
  final Map<DateTime, DiarySummaryDay> dayMap;

  /// 현재 선택된 날짜. null이면 선택 표시 없음.
  final DateTime? selectedDate;

  /// 날짜 셀 탭 콜백.
  // TODO: 로직 연결 지점 — 선택 날짜 상태 갱신 및 해당 기록 상세/에디터로 이동
  final void Function(DateTime date) onDateTap;

  /// 이전 달 이동 콜백. null이면 chevron 버튼 비활성.
  // TODO: 로직 연결 지점 — 표시 월 상태 1개월 감소
  final VoidCallback? onPrevMonth;

  /// 다음 달 이동 콜백. null이면 chevron 버튼 비활성.
  // TODO: 로직 연결 지점 — 표시 월 상태 1개월 증가
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    // mainAxisSize.min을 두지 않아 부모(Expanded)의 세로 공간을 모두 차지하고,
    // 그리드를 Expanded로 늘려 남는 높이를 자연스럽게 채운다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 연/월 제목 + 이전·다음 달 버튼
        _MonthHeader(
          month: month,
          onPrevMonth: onPrevMonth,
          onNextMonth: onNextMonth,
        ),
        const SizedBox(height: AppSpacing.sm),
        // 요일 레이블 행 (일~토)
        const _WeekdayRow(),
        const SizedBox(height: AppSpacing.xs),
        // 날짜 셀 그리드 — 남는 세로 공간을 채운다.
        Expanded(
          child: _DateGrid(
            month: month,
            dayMap: dayMap,
            selectedDate: selectedDate,
            onDateTap: onDateTap,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _MonthHeader
// ─────────────────────────────────────────────────────────────

/// 월 헤더: 연/월 텍스트(좌) + 이전·다음 달 chevron 버튼(우)
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
        // 연/월 텍스트 — 연도는 ink, 월 숫자만 primary 강조
        // Text.rich를 사용해 find.text()로 검색 가능하게 유지한다.
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
        // 이전 달 버튼 (null → Material 3 비활성 처리 자동)
        IconButton(
          tooltip: '이전 달',
          onPressed: onPrevMonth,
          icon: const Icon(Icons.chevron_left),
          color: AppColors.ink,
        ),
        // 다음 달 버튼
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

/// 요일 레이블 행 (일~토, 일요일 시작).
/// 일=웜레드, 토=뮤트퍼플, 평일=inkMuted — 과하지 않은 구분.
class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_kWeekdays.length, (index) {
        // 요일별 색상 (Dart 3 switch 표현식)
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
                fontWeight: FontWeight.w600, // 시안 기준 600
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

/// 날짜 셀 그리드. 7열 고정, 최대 6주(42칸).
class _DateGrid extends StatelessWidget {
  const _DateGrid({
    required this.month,
    required this.dayMap,
    required this.onDateTap,
    this.selectedDate,
  });

  final DateTime month;

  /// 날짜(시간=0 정규화) → 감정 요약 맵.
  final Map<DateTime, DiarySummaryDay> dayMap;

  final DateTime? selectedDate;
  final void Function(DateTime date) onDateTap;

  @override
  Widget build(BuildContext context) {
    final int offset = _firstWeekdayOffset(month);
    final int daysCount = _daysInMonth(month);
    // 6주(42칸) 상한 — 어떤 달도 오버플로우 없음
    final int totalCells = ((offset + daysCount) / 7).ceil() * 7;
    final int rows = totalCells ~/ 7; // 이 달의 주(행) 수 (5 또는 6)

    // 시간을 버린 '오늘'(미래 날짜 비활성 비교용).
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 가용 높이를 행 수로 나눠 행 높이를 정한다. 최소(_kDayCellHeight)~최대
        // (_kDayCellMaxHeight)로 클램프해 작은 화면 오버플로우·긴 화면 과신장을 막는다.
        final double rowHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight / rows)
                .clamp(_kDayCellHeight, _kDayCellMaxHeight)
            : _kDayCellHeight;

        return GridView.builder(
          // bounded 높이(Expanded)를 받으므로 shrinkWrap 불필요.
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: rowHeight, // 가용 높이에 맞춰 채움
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
        final int dayNumber = index - offset + 1;

        // 그리드 앞쪽 빈 칸 및 마지막 채우기 칸 — 빈 영역
        if (dayNumber < 1 || dayNumber > daysCount) {
          return const SizedBox.shrink();
        }

        final DateTime date = DateTime(month.year, month.month, dayNumber);
        final int weekdayIndex = index % 7; // 0=일, 6=토

        // 해당 날짜의 감정 요약(없으면 null — 기록 없는 날).
        // 키는 생성자에서 DateTime(y, m, d)로 정규화되어 있으므로 직접 조회 가능.
        final DiarySummaryDay? summaryDay = dayMap[date];

        return _DayCell(
          day: dayNumber,
          date: date,
          isToday: _isSameDay(date, today),
          isSelected:
              selectedDate != null && _isSameDay(date, selectedDate!),
          summaryDay: summaryDay,
          // 오늘 이후(미래)는 작성/조회 대상이 아니므로 비활성.
          isDisabled: date.isAfter(today),
          weekdayIndex: weekdayIndex,
          onTap: () => onDateTap(date),
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

/// 캘린더 날짜 셀.
///
/// 시각 상태 (우선순위 순):
/// - **오늘**: primary 채운 원 + 흰 글자 (최우선)
/// - **기록 있는 날(DONE·DRAFT)**: hairline 링 원 + 하단 5px 점
///   - DONE: accent(바이올렛) 점
///   - DRAFT: inkMuted 점
/// - **선택됨(기록 없는 날)**: primarySoft 둥근 사각형
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.date,
    required this.isToday,
    required this.isSelected,
    this.summaryDay,
    required this.isDisabled,
    required this.weekdayIndex,
    required this.onTap,
  });

  final int day;
  final DateTime date;
  final bool isToday;
  final bool isSelected;

  /// 해당 날짜의 기록 요약. null이면 기록 없는 날(기본 스타일).
  final DiarySummaryDay? summaryDay;

  /// 미래 날짜 여부. true이면 흐리게 표시하고 탭을 막는다(작성/조회 불가).
  final bool isDisabled;

  /// 그리드 내 요일 위치 (0=일, 6=토) — 텍스트 색 결정에 사용
  final int weekdayIndex;

  final VoidCallback onTap;

  /// 날짜 숫자 색상 결정
  Color _dayTextColor() {
    if (isDisabled) return AppColors.inkMuted; // 미래 날짜 — 흐리게(최우선)
    if (isToday) return AppColors.surface;     // 채운 원 위 흰 글자
    if (weekdayIndex == 0) return AppColors.error;   // 일요일 — error 적색
    if (weekdayIndex == 6) return AppColors.primary; // 토요일 — primary 블루
    return AppColors.ink;
  }

  /// 날짜 배경 데코레이션 결정 (우선순위: 오늘 > 기록 있음 > 선택)
  ///
  /// 시안: 오늘=primary 채운 원, 기록 있는 날(DONE·DRAFT 모두)=hairline 링 원.
  /// 하단 5px 점으로 DONE/DRAFT를 구분한다([_buildEmotionIndicator] 참고).
  BoxDecoration? _buildBgDecoration() {
    // 오늘 — primary 채운 원 (모든 상태 위에 덮어씀)
    if (isToday) {
      return const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      );
    }
    // 기록 있는 날(DONE·DRAFT) — hairline 링 원 (inset 0 0 0 1px hairline)
    if (summaryDay != null) {
      return BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline, width: 1.0),
      );
    }
    // 선택됨(기록 없는 날)
    if (isSelected) {
      return BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      );
    }
    return null;
  }

  /// 날짜 숫자 아래 5px 상태 점.
  ///
  /// - DONE: accent(바이올렛) 점
  /// - DRAFT/PENDING: inkMuted 점
  /// - 기록 없음: null(빈 공간 유지)
  ///
  /// (마스코트는 작아서 식별이 어려워 상세 화면 영상으로 옮겼고, 캘린더는 점으로 상태만 구분)
  Widget? _buildEmotionIndicator() {
    if (summaryDay == null) return null;
    final Color dotColor =
        summaryDay!.isDone ? AppColors.accent : AppColors.inkMuted;
    return Center(
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // 접근성 레이블 조합
    final String semanticsLabel =
        '${date.month}월 $day일'
        '${isToday ? ', 오늘' : ''}'
        '${summaryDay?.isDone == true ? ', 기록 있음'
            '${summaryDay!.moodEmoji != null ? ' ${summaryDay!.moodEmoji}' : ''}' : ''}'
        '${summaryDay?.isDraft == true ? ', 임시 저장' : ''}'
        '${isDisabled ? ', 작성 불가' : ''}';

    return Semantics(
      label: semanticsLabel,
      button: !isDisabled,
      child: InkWell(
        // 미래 날짜는 탭 무효(리플도 없음).
        onTap: isDisabled ? null : onTap,
        // 셀 전체를 탭 영역으로 — mainAxisExtent 56dp ≥ 48dp 기준 충족
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── 날짜 숫자 + 배경(원/링/사각형) ──
            Container(
              width: _kDayCellBgSize,
              height: _kDayCellBgSize,
              decoration: _buildBgDecoration(),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 16, // 셀 확대에 맞춰 날짜 숫자도 소폭 키움
                  color: _dayTextColor(),
                  fontWeight:
                      isToday ? FontWeight.w600 : FontWeight.w400,
                  height: 1.0, // 수직 정렬 보정
                ),
              ),
            ),
            const SizedBox(height: 2),
            // ── 감정 이모지 영역 ──
            // 고정 높이로 기록 없는 날과 셀 크기를 동일하게 유지한다.
            SizedBox(
              height: _kEmotionIndicatorHeight,
              child: _buildEmotionIndicator(),
            ),
          ],
        ),
      ),
    );
  }
}
