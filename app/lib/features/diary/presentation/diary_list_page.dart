import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../data/dto/diary_dto.dart';
import 'providers/diary_providers.dart';
import 'widgets/diary_list_tile.dart';

const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 기록 목록 화면.
///
/// 캘린더와 동일하게 **월 단위**로 보여준다. 상단 ‹ › 헤더(또는 좌우 스와이프)로 월을
/// 이동하면 해당 월의 기록을 written_date 역순으로 표시한다(하루 1기록이라 페이징 없음).
///
/// 데이터는 [monthDiariesProvider]를 watch한다. 작성/수정/삭제 시 해당 프로바이더를
/// invalidate하면, 탭이 살아 있어도(IndexedStack) **즉시 실시간 갱신**된다.
class DiaryListPage extends ConsumerStatefulWidget {
  const DiaryListPage({super.key});

  @override
  ConsumerState<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends ConsumerState<DiaryListPage> {
  /// 현재 표시 중인 달(1일 기준).
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);
  }

  /// 'yyyy-MM' (월 목록 조회 인자).
  String get _yearMonth =>
      '${_displayMonth.year.toString().padLeft(4, '0')}-'
      '${_displayMonth.month.toString().padLeft(2, '0')}';

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

  String _dateText(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  /// 날짜를 에디터 라우트 쿼리 형식('yyyy-MM-dd')으로 변환한다.
  String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(monthDiariesProvider(_yearMonth));

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          actions: [
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
            children: [
              // ── 페이지 타이틀 헤더 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 주제목: PoorStory 26px ink
                    const Text(
                      '지나온 날들',
                      style: TextStyle(
                        fontFamily: 'PoorStory',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.01 * 26,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 부제목: 총 N개의 기록 (데이터가 로드되면 업데이트)
                    Text(
                      '총 ${async.asData?.value.length ?? 0}개의 기록',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // 월 이동 헤더(캘린더와 동일 패턴).
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  0,
                ),
                child: _MonthHeader(
                  month: _displayMonth,
                  onPrev: () => _changeMonth(-1),
                  // 이번 달이면 다음 달 chevron 비활성(미래 달 차단).
                  onNext: _atCurrentMonth ? null : () => _changeMonth(1),
                ),
              ),
              Expanded(
                // 좌우 스와이프로도 월 이동(캘린더와 동일 감각).
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v < 0) {
                      _changeMonth(1);
                    } else if (v > 0) {
                      _changeMonth(-1);
                    }
                  },
                  child: _buildBody(async),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<Diary>> async) {
    return async.when(
      loading: () => const LoadingView(),
      error: (_, _) => ErrorView(
        message: '목록을 불러오지 못했어요',
        onRetry: () => ref.invalidate(monthDiariesProvider(_yearMonth)),
      ),
      data: (items) {
        if (items.isEmpty) return const _EmptyMonth();
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(monthDiariesProvider(_yearMonth)),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final diary = items[index];
              return DiaryListTile(
                dateText: _dateText(diary.writtenDate),
                preview: diary.content,
                thumbnailUrl: diary.thumbnailUrl,
                imageCount: diary.imageCount,
                isDraft: diary.isDraft,
                // DRAFT: 에디터로 이동(날짜 기반 수정 재진입), 확정: 상세로 이동.
                onTap: diary.isDraft
                    ? () => context
                        .push('/editor?date=${_dateParam(diary.writtenDate)}')
                    : () => context.push('/diary/${diary.id}'),
              );
            },
          ),
        );
      },
    );
  }
}

/// 빈 상태.
class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth();

  @override
  Widget build(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.book_outlined,
      message: '이 달에 기록된 기억이 없어요',
    );
  }
}

/// 월 이동 헤더: 연/월 텍스트 + 이전·다음 달 chevron. (CalendarMonthView 헤더와 동일 톤.)
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrev;

  /// null이면 다음 달 버튼 비활성(미래 달 차단).
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${month.year}년 ${month.month}월',
            style: textTheme.titleLarge?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: '이전 달',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          color: AppColors.ink,
        ),
        IconButton(
          tooltip: '다음 달',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          color: AppColors.ink,
        ),
      ],
    );
  }
}
