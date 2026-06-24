import 'package:flutter/material.dart';

import 'package:record/core/theme/app_colors.dart';
import 'package:record/core/theme/app_spacing.dart';

// ─────────────────────────────────────────────────────────────
// 파일 내부 상수
// ─────────────────────────────────────────────────────────────

/// 요일 레이블 (일요일 시작)
const List<String> _kWeekdays = ['일', '월', '화', '수', '목', '금', '토'];

/// 일요일 레이블 색상 — 과하지 않은 웜레드
const Color _kSundayLabelColor = Color(0xFFCB6D6D);

/// 토요일 레이블 색상 — 뮤트 퍼플(accent 계열 유지)
const Color _kSaturdayLabelColor = Color(0xFF9B8FD4);

/// 날짜 배경 원/사각형 크기 (dp)
const double _kDayCellBgSize = 34.0;

/// 감정 dot 직경 (dp).
///
/// 이 dot은 이 앱의 시그니처 시각 요소.
/// 현재는 accent 단색이지만, Phase 4 감정 분석 이후
/// emotionColor 파라미터로 주입되어 각 날짜의 감정 색을 표현한다.
const double _kEmotionDotSize = 6.0;

/// 날짜 셀 고정 높이 (dp).
/// 34(원) + 3(갭) + 6(dot) + 상하 여백 = 52
const double _kDayCellHeight = 52.0;

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
/// ### MainCalendarPage에서 사용 예
/// ```dart
/// CalendarMonthView(
///   month: DateTime(2026, 6),
///   markedDates: {DateTime(2026, 6, 3), DateTime(2026, 6, 10)},
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
    required this.markedDates,
    this.selectedDate,
    required this.onDateTap,
    this.onPrevMonth,
    this.onNextMonth,
  });

  /// 표시할 달(1일 기준). 연·월만 의미를 가진다.
  final DateTime month;

  /// 기록이 있는 날짜 집합 (연·월·일 기준, 시간 무시).
  /// 포함된 날짜의 셀 아래에 accent dot이 표시된다.
  final Set<DateTime> markedDates;

  /// 현재 선택된 날짜. null이면 선택 표시 없음.
  final DateTime? selectedDate;

  /// 날짜 셀 탭 콜백.
  // TODO: 로직 연결 지점 — 선택 날짜 상태 갱신 및 해당 일기 상세/에디터로 이동
  final void Function(DateTime date) onDateTap;

  /// 이전 달 이동 콜백. null이면 chevron 버튼 비활성.
  // TODO: 로직 연결 지점 — 표시 월 상태 1개월 감소
  final VoidCallback? onPrevMonth;

  /// 다음 달 이동 콜백. null이면 chevron 버튼 비활성.
  // TODO: 로직 연결 지점 — 표시 월 상태 1개월 증가
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        // 날짜 셀 그리드
        _DateGrid(
          month: month,
          markedDates: markedDates,
          selectedDate: selectedDate,
          onDateTap: onDateTap,
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
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        // 연/월 텍스트 — 남은 공간을 모두 차지
        Expanded(
          child: Text(
            '${month.year}년 ${month.month}월',
            style: textTheme.titleLarge?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
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
    final textTheme = Theme.of(context).textTheme;

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
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
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
    required this.markedDates,
    required this.onDateTap,
    this.selectedDate,
  });

  final DateTime month;
  final Set<DateTime> markedDates;
  final DateTime? selectedDate;
  final void Function(DateTime date) onDateTap;

  @override
  Widget build(BuildContext context) {
    final int offset = _firstWeekdayOffset(month);
    final int daysCount = _daysInMonth(month);
    // 6주(42칸) 상한 — 어떤 달도 오버플로우 없음
    final int totalCells = ((offset + daysCount) / 7).ceil() * 7;

    // 이 달에 기록 있는 '일' 번호 집합 — build 중 O(1) 조회
    final Set<int> markedDays = markedDates
        .where((d) => d.year == month.year && d.month == month.month)
        .map((d) => d.day)
        .toSet();

    final DateTime today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: _kDayCellHeight, // 고정 높이 — 화면 너비 무관
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

        return _DayCell(
          day: dayNumber,
          date: date,
          isToday: _isSameDay(date, today),
          isSelected:
              selectedDate != null && _isSameDay(date, selectedDate!),
          isMarked: markedDays.contains(dayNumber),
          weekdayIndex: weekdayIndex,
          onTap: () => onDateTap(date),
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
/// 시각 상태:
/// - **오늘**: accent 채운 원 + 흰 글자
/// - **선택됨**: accentSoft 둥근 사각형 배경
/// - **기록 있음**: 숫자 아래 accent dot 표시
/// - 오늘 + 선택: 오늘 스타일 우선 (원이 이미 명확히 구분됨)
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.isMarked,
    required this.weekdayIndex,
    required this.onTap,
  });

  final int day;
  final DateTime date;
  final bool isToday;
  final bool isSelected;

  /// 기록 있는 날 여부.
  /// true이면 숫자 아래 dot을 표시.
  /// [dot = 앱 시그니처 요소 — Phase 4에서 감정 색으로 교체 예정]
  final bool isMarked;

  /// 그리드 내 요일 위치 (0=일, 6=토) — 텍스트 색 결정에 사용
  final int weekdayIndex;

  final VoidCallback onTap;

  /// 날짜 숫자 색상 결정
  Color _dayTextColor() {
    if (isToday) return AppColors.surface; // 채운 원 위 흰 글자
    if (weekdayIndex == 0) return _kSundayLabelColor;
    if (weekdayIndex == 6) return _kSaturdayLabelColor;
    return AppColors.ink;
  }

  /// 날짜 배경 데코레이션 결정
  ///
  /// - today: accent 채운 원
  /// - selected(오늘 제외): accentSoft 둥근 사각형
  /// - 그 외: null
  BoxDecoration? _buildBgDecoration() {
    if (isToday) {
      return const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      );
    }
    if (isSelected) {
      return BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // 접근성 레이블 조합
    final String semanticsLabel =
        '${date.month}월 $day일'
        '${isToday ? ', 오늘' : ''}'
        '${isMarked ? ', 기록 있음' : ''}';

    return Semantics(
      label: semanticsLabel,
      button: true,
      child: InkWell(
        onTap: onTap,
        // 셀 전체를 탭 영역으로 — mainAxisExtent 52dp ≥ 48dp 기준 충족
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── 날짜 숫자 + 배경(원/사각형) ──
            Container(
              width: _kDayCellBgSize,
              height: _kDayCellBgSize,
              decoration: _buildBgDecoration(),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: textTheme.bodyMedium?.copyWith(
                  color: _dayTextColor(),
                  fontWeight:
                      isToday ? FontWeight.w600 : FontWeight.w400,
                  height: 1.0, // 수직 정렬 보정
                ),
              ),
            ),
            const SizedBox(height: 3),
            // ── 감정 dot ──
            // 현재: accent 단색 dot.
            // Phase 4 TODO: 로직 연결 지점 —
            //   Map<DateTime, Color>? emotionColors 파라미터를 CalendarMonthView에 추가하고
            //   여기서 해당 날짜의 감정 색을 dot에 적용한다.
            SizedBox(
              height: _kEmotionDotSize,
              child: isMarked
                  ? Container(
                      width: _kEmotionDotSize,
                      height: _kEmotionDotSize,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
