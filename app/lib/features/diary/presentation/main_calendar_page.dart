import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/api_config.dart';
import '../../../core/notifications/notification_permission_prompt.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../../shared/widgets/write_choice_sheet.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../data/dto/diary_dto.dart';
import 'providers/diary_providers.dart';
import 'widgets/calendar_month_view.dart';

/// 메인(캘린더) 화면.
///
/// 요약 provider(API)로 작성 날짜에 dot을 표시하고, 날짜 탭 시
/// 기록 존재 여부에 따라 상세/에디터로 분기한다. (표현은 [CalendarMonthView] 담당.)
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

    // 로그인 후 캘린더 첫 진입 시 알림 권한 요청(내부 플래그로 1회만 노출).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeAskNotificationPermission(context, ref);
    });
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

  /// 날짜 탭: 해당 날짜 기록 상태에 따라 상세/작성 선택으로 분기.
  ///
  /// - 확정 기록(!isDraft): 기존대로 상세 화면으로 이동.
  /// - 그 외(DRAFT·없음): 작성 선택 시트를 띄운다. 오늘이면 작심삼일 시작 가능,
  ///   과거 날짜면 시트는 뜨되 작심삼일 카드는 비활성이고 글 작성만 가능하다.
  Future<void> _onDateTap(DateTime date) async {
    // 미래 날짜 방어(캘린더 셀이 이미 막지만 이중 안전).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date.isAfter(today)) return;

    final diary = await ref.read(diaryRepositoryProvider).getByDate(date);
    if (!mounted) return;

    if (diary != null && !diary.isDraft) {
      // 확정 기록 → 상세 화면
      await context.push('/diary/${diary.id}');
      if (!mounted) return;
      _refreshSummary();
      return;
    }

    // DRAFT이거나 없으면 작성 선택 시트. 작심삼일은 오늘 날짜에만 허용.
    final isToday = _isSameDay(date, today);
    final choice = await showWriteChoiceSheet(context, allowResolution: isToday);
    if (!mounted || choice == null) return;

    switch (choice) {
      case WriteChoice.diary:
        // 같은 날짜 DRAFT는 에디터에서 프리필된다.
        await context.push('/editor?date=${_dateParam(date)}');
      case WriteChoice.resolution:
        await context.push('/resolution/new?date=${_dateParam(date)}');
    }
    if (!mounted) return;
    // 작성/수정/삭제 결과를 캘린더 dot에 반영.
    _refreshSummary();
  }

  /// FAB: 작성 선택 시트를 띄워 글 작성/작심삼일 시작으로 분기(모두 오늘 날짜).
  Future<void> _onWriteToday() async {
    final choice = await showWriteChoiceSheet(context);
    if (!mounted || choice == null) return;

    final todayParam = _dateParam(DateTime.now());
    switch (choice) {
      case WriteChoice.diary:
        await context.push('/editor?date=$todayParam');
      case WriteChoice.resolution:
        await context.push('/resolution/new?date=$todayParam');
    }
    if (!mounted) return;
    _refreshSummary();
  }

  /// 연·월·일만 비교하는 날짜 동등 비교.
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(monthlySummaryProvider(_yearMonth));
    // summary.days를 DateTime 정규화 키(시간=0) → DiarySummaryDay 맵으로 변환한다.
    // 데이터 도착 전 또는 오류 시 빈 맵 — 캘린더 렌더·월 이동은 항상 동작.
    final dayMap = <DateTime, DiarySummaryDay>{};
    for (final day in summary.asData?.value.days ?? <DiarySummaryDay>[]) {
      final d = DateTime.parse(day.date);
      dayMap[DateTime(d.year, d.month, d.day)] = day;
    }

    // 헤더 감성 메시지용 — 확정 기록(DRAFT 제외) 수. 데이터 도착 전엔 hasData=false로 중립 문구.
    final summaryData = summary.asData?.value;
    final recordCount =
        summaryData?.days.where((d) => !d.isDraft).length ?? 0;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 인사말 헤더 — 닉네임 + 이번 달 기록 수 기반 감성 메시지 ──
            _GreetingSection(
              count: recordCount,
              daysInMonth: DateUtils.getDaysInMonth(
                _displayMonth.year, _displayMonth.month,
              ),
              isCurrentMonth: _atCurrentMonth,
              month: _displayMonth.month,
              hasData: summaryData != null,
            ),
            // ── 캘린더 본문(나머지 공간 차지) ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm,
                  AppSpacing.lg, AppSpacing.sm,
                ),
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
                    dayMap: dayMap,
                    onDateTap: _onDateTap,
                    onPrevMonth: () => _changeMonth(-1),
                    // 이번 달이면 다음 달 chevron 비활성(미래 달 차단).
                    onNextMonth: _atCurrentMonth ? null : () => _changeMonth(1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onWriteToday,
        child: const Icon(Icons.edit),
      ),
      ),
    );
  }
}

/// 월 요약 로딩/에러 시 보여줄 중립 폴백 문구(월 이동 중 깜빡임 방지).
const String _kGreetingFallback = '어떻게 기록할까요?';

/// 그 달 기록 수 기반 감성 헤더 문구를 만든다.
///
/// [count]는 확정 기록 수(DRAFT 제외), [daysInMonth]는 그 달 총 일수,
/// [isCurrentMonth]면 '이번 달' 톤·아니면 '[month]월' 톤, [month]는 1~12.
///
/// 단계: 0 / 1 / 2~중반 / 절반~ / 꽉 참(=일수와 동일). 하루 1기록 원칙이라
/// [count]는 [daysInMonth]를 넘지 않는다. 위젯에서 분리해 단위 테스트가 쉽도록 top-level.
String diaryCountGreeting({
  required int count,
  required int daysInMonth,
  required bool isCurrentMonth,
  required int month,
}) {
  // 절반 임계값(올림). 예: 30일 → 15.
  final half = (daysInMonth + 1) ~/ 2;

  if (count <= 0) {
    return isCurrentMonth
        ? '아직 이번 달엔 기록된 기억이 없어요.\n오늘 있었던 일을 적어볼까요?'
        : '$month월엔 기록된 기억이 없어요.';
  }
  if (count == 1) {
    return isCurrentMonth ? '이번 달 첫 기억을 남겼어요 ✨' : '$month월엔 기억 1개를 남겼어요.';
  }
  if (count >= daysInMonth) {
    return isCurrentMonth
        ? '이번 달은 정말 많은 일들이 있었네요.\n이번 달도 수고했어요 🌙'
        : '$month월은 정말 많은 일들이 있었네요.\n그달도 수고 많았어요 🌙';
  }
  if (count >= half) {
    return isCurrentMonth ? '벌써 $count개의 기억이 쌓였어요.' : '$month월엔 기억 $count개가 쌓였어요.';
  }
  return isCurrentMonth ? '이번 달의 기록된 기억은 $count개예요.' : '$month월엔 기억 $count개를 남겼어요.';
}

/// 헤더 헤드라인 공통 스타일 — 닉네임 줄과 감성 메시지 줄이 동일하게 사용한다.
/// PoorStory 26 w700 ink, 살짝 음수 자간.
const TextStyle _kGreetingHeadlineStyle = TextStyle(
  fontFamily: 'PoorStory',
  fontSize: 26,
  fontWeight: FontWeight.w700,
  color: AppColors.ink,
  letterSpacing: -0.01 * 26,
  height: 1.25,
);

/// 캘린더 상단 인사말 헤더.
///
/// '{닉네임}님'(닉네임 있을 때만) + 그 달 기록 수에 반응하는 감성 메시지.
/// 두 줄 모두 [_kGreetingHeadlineStyle](PoorStory 26)로 한 덩어리 헤드라인처럼 보인다.
///
/// 닉네임은 [myProfileProvider]에서 읽는다. 로딩/오류 시 닉네임 줄 없이 메시지만 표시.
/// 주 문구는 [count](DRAFT 제외 확정 기록 수)·[daysInMonth]·[isCurrentMonth]·
/// [month]로 [diaryCountGreeting]에서 산출한다. [hasData]가 false면(요약 로딩/에러)
/// 중립 폴백 문구를 보여 월 이동 중 깜빡임을 막는다.
class _GreetingSection extends ConsumerWidget {
  const _GreetingSection({
    required this.count,
    required this.daysInMonth,
    required this.isCurrentMonth,
    required this.month,
    required this.hasData,
  });

  /// 보고 있는 달의 확정 기록 수(DRAFT 제외).
  final int count;

  /// 보고 있는 달의 총 일수(꽉 참 판정용).
  final int daysInMonth;

  /// 보고 있는 달이 현재(이번) 달인지 — '이번 달' vs '{month}월' 톤 분기.
  final bool isCurrentMonth;

  /// 보고 있는 달(1~12) — 과거 달 문구의 'N월'에 사용.
  final int month;

  /// 월 요약 데이터 도착 여부. false면 중립 폴백.
  final bool hasData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = ref.watch(myProfileProvider).asData?.value.nickname ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 닉네임 줄 — 메시지와 같은 크기. 닉네임 없으면 줄 자체를 생략.
          if (nickname.isNotEmpty) ...[
            Text('$nickname님', style: _kGreetingHeadlineStyle),
            const SizedBox(height: 2),
          ],
          // 주 문구: 기록 수 기반 감성 메시지 — 닉네임 줄과 동일 스타일
          Text(
            hasData
                ? diaryCountGreeting(
                    count: count,
                    daysInMonth: daysInMonth,
                    isCurrentMonth: isCurrentMonth,
                    month: month,
                  )
                : _kGreetingFallback,
            style: _kGreetingHeadlineStyle,
          ),
        ],
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
