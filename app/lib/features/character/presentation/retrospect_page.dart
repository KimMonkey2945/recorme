import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/emotion_palette.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/retrospect.dart';
import 'providers/character_providers.dart';

/// 월간 회고(F032 — ★ 락인). 이달의 기록·연속일·감정 분포·획득 코인·획득 아이템을 한 장으로 보여준다.
///
/// **데이터가 쌓일수록 떠나기 어려워지는 구조**를 가시화한다. 성장은 코인·획득 아이템으로만 표현하며
/// (경험치/레벨 폐기), 감정은 이 화면의 분포 통계에만 쓰인다(프리셋 + 직접 입력 라벨 혼재).
/// 캐릭터 홈에서 진입하며, 월 이동(이전/다음)이 가능하되 미래 달은 막는다.
class RetrospectPage extends ConsumerStatefulWidget {
  const RetrospectPage({super.key, this.initialYearMonth});

  /// 초기 표시 월(YYYY-MM). 생략 시 이번 달.
  final String? initialYearMonth;

  @override
  ConsumerState<RetrospectPage> createState() => _RetrospectPageState();
}

class _RetrospectPageState extends ConsumerState<RetrospectPage> {
  /// 현재 표시 중인 (년, 월).
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final parsed = _parse(widget.initialYearMonth);
    _year = parsed?.$1 ?? now.year;
    _month = parsed?.$2 ?? now.month;
  }

  /// 'YYYY-MM' 파싱(실패 시 null).
  (int, int)? _parse(String? ym) {
    if (ym == null) return null;
    final parts = ym.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return null;
    return (y, m);
  }

  String get _yearMonth =>
      '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}';

  /// 이번 달(미래 이동 차단 기준)인지.
  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  void _goPrev() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
    });
  }

  void _goNext() {
    if (_isCurrentMonth) return; // 미래 달 차단
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(retrospectProvider(_yearMonth));

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('이달의 기록'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _MonthSelector(
                label: '$_year년 $_month월',
                onPrev: _goPrev,
                // 이번 달이면 다음 버튼 비활성(미래 차단).
                onNext: _isCurrentMonth ? null : _goNext,
              ),
              Expanded(
                child: async.when(
                  loading: () => const LoadingView(message: '회고를 불러오는 중...'),
                  error: (_, _) => ErrorView(
                    message: '회고를 불러오지 못했어요',
                    onRetry: () =>
                        ref.invalidate(retrospectProvider(_yearMonth)),
                  ),
                  data: (r) => _RetrospectBody(retrospect: r),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 월 이동 셀렉터(이전/다음 화살표 + 현재 월 라벨). [onNext]가 null이면 다음 버튼 비활성(미래 차단).
class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: '이전 달',
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음 달',
          ),
        ],
      ),
    );
  }
}

/// 회고 본문 — 기록 0건이면 빈 상태, 아니면 요약·감정 분포·획득 아이템을 세로로 쌓는다.
class _RetrospectBody extends StatelessWidget {
  const _RetrospectBody({required this.retrospect});

  final Retrospect retrospect;

  @override
  Widget build(BuildContext context) {
    final r = retrospect;
    if (r.confirmedCount == 0) {
      return const EmptyStateView(
        icon: Icons.calendar_month_outlined,
        message: '이번 달 기록이 아직 없어요',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ── 요약 지표 ──
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.edit_note,
                value: '${r.confirmedCount}',
                unit: '일',
                label: '기록',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.local_fire_department,
                value: '${r.consecutiveDaysMax}',
                unit: '일',
                label: '최장 연속',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.emoji_events,
                value: '${r.resolutionSuccessCount}',
                unit: '회',
                label: '작심삼일 완주',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.monetization_on,
                value: '${r.coinEarned}',
                unit: '',
                label: '획득 코인',
              ),
            ),
          ],
        ),

        // ── 감정 분포 ──
        if (r.emotions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle('감정 분포'),
          const SizedBox(height: AppSpacing.sm),
          _EmotionDistribution(emotions: r.emotions),
        ],

        // ── 획득 아이템 ──
        if (r.unlockedItems.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle('이번 달 획득한 아이템'),
          const SizedBox(height: AppSpacing.sm),
          _UnlockedItemsGrid(items: r.unlockedItems),
        ],
      ],
    );
  }
}

/// 요약 지표 타일(아이콘 + 큰 값 + 단위 + 라벨).
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.inkAlt),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  unit,
                  style: const TextStyle(fontSize: 14, color: AppColors.inkAlt),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.inkAlt),
          ),
        ],
      ),
    );
  }
}

/// 섹션 제목.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}

/// 감정 분포 — 감정별 비율 막대(많은 순). 프리셋/커스텀 색은 [EmotionPalette]로 통일.
class _EmotionDistribution extends StatelessWidget {
  const _EmotionDistribution({required this.emotions});

  final List<EmotionStat> emotions;

  @override
  Widget build(BuildContext context) {
    final maxCount =
        emotions.fold<int>(1, (m, e) => e.count > m ? e.count : m);
    return Column(
      children: [
        for (final e in emotions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _EmotionRow(stat: e, maxCount: maxCount),
          ),
      ],
    );
  }
}

/// 감정 1건 행 — 색 점 + 라벨 + 비율 막대 + 개수.
class _EmotionRow extends StatelessWidget {
  const _EmotionRow({required this.stat, required this.maxCount});

  final EmotionStat stat;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final color = EmotionPalette.chipColor(code: stat.code, label: stat.label);
    final ratio = maxCount == 0 ? 0.0 : stat.count / maxCount;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 64,
          child: Text(
            stat.displayLabel,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: AppColors.ink),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // 비율 막대.
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.hairline,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${stat.count}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// 이번 달 획득 아이템 그리드(썸네일 + 이름).
class _UnlockedItemsGrid extends StatelessWidget {
  const _UnlockedItemsGrid({required this.items});

  final List<UnlockedItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _UnlockedItemTile(item: items[i]),
    );
  }
}

/// 획득 아이템 1개 타일.
class _UnlockedItemTile extends StatelessWidget {
  const _UnlockedItemTile({required this.item});

  final UnlockedItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Expanded(
            child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                ? Image.asset(
                    item.imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.checkroom, color: AppColors.inkAlt),
                  )
                : const Icon(Icons.checkroom, color: AppColors.inkAlt),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.nameKo,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.inkAlt),
          ),
        ],
      ),
    );
  }
}
