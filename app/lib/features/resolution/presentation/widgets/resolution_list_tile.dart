import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/resolution.dart';
import 'resolution_status_badge.dart';

// ─────────────────────────────────────────────────────────────
// 파일 레벨 상수 (diary_list_tile 카드 스타일과 동일 톤)
// ─────────────────────────────────────────────────────────────

const BorderRadius _kCardBorderRadius = BorderRadius.all(
  Radius.circular(AppRadius.card),
);

const RoundedRectangleBorder _kCardShape = RoundedRectangleBorder(
  borderRadius: _kCardBorderRadius,
);

/// 카드 그림자 — 블랙 ~5%, blur 12, offset (0, 4).
const List<BoxShadow> _kCardShadow = [
  BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  ),
];

/// 요일 레이블(기간 텍스트용).
const List<String> _kWeekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 결심 목록 항목 타일.
///
/// 흰 surface 카드 위에 제목 + 기간 + 3칸 진행 도트 + 상태 배지를 표시하는 순수
/// 표현 위젯이다. streakSeq가 2 이상이면 "🔥N연속" 라벨을 함께 보여준다.
/// 탭 동작은 [onTap]으로 외부에 위임한다(diary_list_tile 관례).
/// **null이면 탭 불가**(잉크 리플도 생기지 않는다) — 친구 둘러보기처럼 상세 진입을 막아야 하는
/// 읽기 전용 화면에서 쓴다(상세 화면에는 체크·연장 같은 쓰기 액션이 있어 진입시키면 안 된다).
class ResolutionListTile extends StatelessWidget {
  const ResolutionListTile({
    super.key,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.streakSeq,
    required this.dayStatuses,
    this.onTap,
  });

  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final ResolutionStatus status;

  /// 연장 체인 순번(1이면 최초, 2 이상이면 "N연속" 라벨 노출).
  final int streakSeq;

  /// 1·2·3일차 체크 상태(3칸 진행 도트 렌더용).
  final List<CheckStatus> dayStatuses;

  final VoidCallback? onTap;

  /// 'N월 N일 (요일)' 짧은 날짜 표기.
  String _shortDate(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_kWeekdays[d.weekday - 1]})';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: _kCardBorderRadius,
        boxShadow: _kCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        shape: _kCardShape,
        child: InkWell(
          onTap: onTap,
          customBorder: _kCardShape,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 제목 + 상태 배지 ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ResolutionStatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // ── 기간 + 연속 라벨 ──
                Row(
                  children: [
                    Text(
                      '${_shortDate(startDate)} ~ ${_shortDate(endDate)}',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.inkAlt,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (streakSeq >= 2) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '🔥$streakSeq연속',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // ── 3칸 진행 도트 ──
                _DayDots(dayStatuses: dayStatuses),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 3일치 진행 상태를 가로 도트 3칸으로 표현한다.
///
/// 상태색: DONE=success, MISSED=error, 그 외(PENDING/미지)=hairline.
class _DayDots extends StatelessWidget {
  const _DayDots({required this.dayStatuses});

  final List<CheckStatus> dayStatuses;

  Color _dotColor(CheckStatus? status) {
    switch (status) {
      case CheckStatus.done:
        return AppColors.success;
      case CheckStatus.missed:
        return AppColors.error;
      case CheckStatus.pending:
      case CheckStatus.unknown:
      case null:
        return AppColors.hairline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final status = i < dayStatuses.length ? dayStatuses[i] : null;
        return Padding(
          padding: EdgeInsets.only(right: i < 2 ? AppSpacing.sm : 0),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _dotColor(status),
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}
