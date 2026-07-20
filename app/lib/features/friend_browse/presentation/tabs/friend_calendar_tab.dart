import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../diary/data/dto/diary_dto.dart';
import '../../../diary/presentation/widgets/calendar_month_view.dart';
import '../providers/friend_browse_providers.dart';

/// 둘러보기 — 친구의 캘린더(읽기 전용).
///
/// 내 캘린더와 달리 **작성 FAB·작성 선택 시트·로그아웃·지난 기록이 없다**.
/// 날짜를 탭하면 본인 전용 상세(`/diary/:id`)가 아니라 **viewer-aware 상세(`/feed/diary/:id`)** 로 간다.
///
/// 서버는 공개 기록(FRIENDS·PUBLIC)만 내려주므로 PRIVATE 기록이 있는 날은 dayMap 에 없다
/// → 점도 안 찍히고 탭해도 아무 일이 없다(요구사항: PRIVATE 는 "아예 없는 날처럼" 보인다).
class FriendCalendarTab extends ConsumerStatefulWidget {
  const FriendCalendarTab({super.key, required this.userUuid, this.nickname});

  final String userUuid;
  final String? nickname;

  @override
  ConsumerState<FriendCalendarTab> createState() => _FriendCalendarTabState();
}

class _FriendCalendarTabState extends ConsumerState<FriendCalendarTab> {
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);
  }

  String get _yearMonth =>
      '${_displayMonth.year.toString().padLeft(4, '0')}-'
      '${_displayMonth.month.toString().padLeft(2, '0')}';

  DateTime get _maxMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  bool get _atCurrentMonth =>
      _displayMonth.year == _maxMonth.year &&
      _displayMonth.month == _maxMonth.month;

  void _changeMonth(int delta) {
    final candidate = DateTime(_displayMonth.year, _displayMonth.month + delta);
    if (candidate.isAfter(_maxMonth)) return; // 미래 달 금지
    setState(() => _displayMonth = candidate);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      friendDiarySummaryProvider((uuid: widget.userUuid, yearMonth: _yearMonth)),
    );

    // 정규화 키(시간=0) → 요약/기록 id 맵. 도착 전·오류면 빈 맵이라 캘린더·월 이동은 항상 동작한다.
    final dayMap = <DateTime, DiarySummaryDay>{};
    final diaryIdMap = <DateTime, int>{};
    for (final day in async.asData?.value ?? const []) {
      final d = DateTime.parse(day.date);
      final key = DateTime(d.year, d.month, d.day);
      dayMap[key] = day.summary;
      diaryIdMap[key] = day.diaryId;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.nickname == null ? '함께 본 기록' : '${widget.nickname}님의 기록',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.inkAlt,
              ),
            ),
          ),
        ),
        // 캘린더 본문(나머지 공간 차지). CalendarMonthView 는 내부에 flex 자식을 쓰므로
        // 높이가 한정된 곳에 놓아야 한다(스크롤뷰에 넣으면 unbounded height 로 레이아웃이 깨진다).
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v > 0) {
                  _changeMonth(-1);
                } else if (v < 0) {
                  _changeMonth(1);
                }
              },
              child: CalendarMonthView(
                month: _displayMonth,
                dayMap: dayMap,
                onDateTap: (date) {
                  final key = DateTime(date.year, date.month, date.day);
                  final id = diaryIdMap[key];
                  // 공개 기록이 없는 날(비공개 포함)은 아무 동작도 하지 않는다.
                  if (id == null) return;
                  context.push('/feed/diary/$id');
                },
                onPrevMonth: () => _changeMonth(-1),
                onNextMonth: _atCurrentMonth ? null : () => _changeMonth(1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
