import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'providers/diary_providers.dart';
import 'widgets/calendar_month_view.dart';

/// 메인(캘린더) 화면.
///
/// 더미 데이터(요약 provider)로 작성 날짜에 dot을 표시하고, 날짜 탭 시
/// 일기 존재 여부에 따라 상세/에디터로 분기한다. (표현은 [CalendarMonthView] 담당.)
class MainCalendarPage extends ConsumerStatefulWidget {
  const MainCalendarPage({super.key});

  @override
  ConsumerState<MainCalendarPage> createState() => _MainCalendarPageState();
}

class _MainCalendarPageState extends ConsumerState<MainCalendarPage> {
  /// 현재 표시 중인 달(1일 기준).
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);
  }

  /// 'yyyy-MM' (요약 provider 인자).
  String get _yearMonth =>
      '${_displayMonth.year.toString().padLeft(4, '0')}-'
      '${_displayMonth.month.toString().padLeft(2, '0')}';

  /// 'yyyy-MM-dd' (에디터 라우트 쿼리).
  String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + delta);
    });
  }

  /// 표시 월 요약을 다시 불러온다(작성/삭제 후 dot 갱신용).
  void _refreshSummary() => ref.invalidate(monthlySummaryProvider(_yearMonth));

  /// 날짜 탭: 해당 날짜 일기가 있으면 상세, 없으면 에디터로 이동.
  Future<void> _onDateTap(DateTime date) async {
    final diary = await ref.read(diaryRepositoryProvider).getByDate(date);
    if (!mounted) return;

    if (diary != null) {
      await context.push('/diary/${diary.id}');
    } else {
      await context.push('/editor?date=${_dateParam(date)}');
    }
    // 작성/수정/삭제 결과를 캘린더 dot에 반영.
    _refreshSummary();
  }

  /// FAB: 오늘 날짜 에디터로 진입.
  Future<void> _onWriteToday() async {
    await context.push('/editor?date=${_dateParam(DateTime.now())}');
    if (!mounted) return;
    _refreshSummary();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(monthlySummaryProvider(_yearMonth));
    // dot 표시용 날짜 집합(데이터 도착 전에는 빈 집합 — 캘린더/월 이동은 항상 동작).
    final markedDates =
        summary.asData?.value.dates.map(DateTime.parse).toSet() ??
            <DateTime>{};

    // 로그인과 동일한 화사한 웜 그라데이션 배경 (앱바 뒤까지 채우기 위해 Container로 감쌈)
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('캘린더'),
          actions: [
            IconButton(
              tooltip: '프로필',
              onPressed: () => context.push('/profile'),
              icon: const Icon(Icons.person_outline_rounded),
            ),
            IconButton(
              tooltip: '로그아웃',
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          // 좌우 스와이프로 월 이동(속도 부호로 방향 판단).
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < 0) {
                _changeMonth(1); // 왼쪽으로 스와이프 → 다음 달
              } else if (v > 0) {
                _changeMonth(-1); // 오른쪽으로 스와이프 → 이전 달
              }
            },
            child: CalendarMonthView(
              month: _displayMonth,
              markedDates: markedDates,
              onDateTap: _onDateTap,
              onPrevMonth: () => _changeMonth(-1),
              onNextMonth: () => _changeMonth(1),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onWriteToday,
        tooltip: '오늘 일기 쓰기',
        child: const Icon(Icons.edit),
      ),
      ),
    );
  }
}
