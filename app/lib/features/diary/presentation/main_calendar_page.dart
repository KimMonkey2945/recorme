import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import 'providers/diary_providers.dart';
import 'widgets/calendar_month_view.dart';

/// 메인(캘린더) 화면.
///
/// 요약 provider(API)로 작성 날짜에 dot을 표시하고, 날짜 탭 시
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

  /// 이번 달(미래 달 이동 상한). 시간 무시, 연·월만.
  DateTime get _maxMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  /// 표시 중인 달이 이번 달이면 true(다음 달 chevron 비활성 판단).
  bool get _atCurrentMonth =>
      _displayMonth.year == _maxMonth.year &&
      _displayMonth.month == _maxMonth.month;

  void _changeMonth(int delta) {
    final candidate =
        DateTime(_displayMonth.year, _displayMonth.month + delta);
    if (candidate.isAfter(_maxMonth)) return; // 미래 달 금지(스와이프·chevron 공통)
    setState(() {
      _displayMonth = candidate;
    });
  }

  /// 표시 월 요약을 다시 불러온다(작성/삭제 후 dot 갱신용).
  void _refreshSummary() => ref.invalidate(monthlySummaryProvider(_yearMonth));

  /// 날짜 탭: 해당 날짜 일기가 있으면 상세, 없으면 에디터로 이동.
  Future<void> _onDateTap(DateTime date) async {
    // 미래 날짜 방어(캘린더 셀이 이미 막지만 이중 안전).
    final now = DateTime.now();
    if (date.isAfter(DateTime(now.year, now.month, now.day))) return;

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
          actions: [
            // 프로필 진입 버튼 — 별도 ConsumerWidget으로 watch 범위를 한정해
            // 프로필 갱신 시 캘린더 본문 전체가 리빌드되지 않게 한다.
            const _AppBarProfileButton(),
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
              // 이번 달이면 다음 달 chevron 비활성(미래 달 차단).
              onNextMonth: _atCurrentMonth ? null : () => _changeMonth(1),
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

/// 앱바 프로필 진입 버튼 — 등록 이미지(없으면 닉네임 이니셜) 아바타. 탭 영역 48dp 확보.
///
/// `myProfileProvider`를 이 위젯에서만 watch해, 프로필 로딩/갱신 시 캘린더 본문이
/// 아니라 이 버튼만 리빌드되게 한다.
class _AppBarProfileButton extends ConsumerWidget {
  const _AppBarProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(myProfileProvider).asData?.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: ProfileAvatar(
            imageUrl: ApiConfig.resolveImageUrl(user?.profileImageUrl),
            radius: 16,
            initial: ProfileAvatar.initialOf(user?.nickname),
            onTap: () => context.push('/profile'),
          ),
        ),
      ),
    );
  }
}
