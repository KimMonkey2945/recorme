import 'package:flutter/material.dart';

import 'package:record/core/theme/app_colors.dart';
import 'package:record/core/theme/app_spacing.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 파일 레벨 상수 — build() 내부에서 반복 생성되지 않도록 추출
// ─────────────────────────────────────────────────────────────────────────────

/// 카드 모서리 반경 (BorderRadius.circular(20) 의 const 동등 표현)
const BorderRadius _kCardBorderRadius = BorderRadius.all(
  Radius.circular(AppRadius.card),
);

/// InkWell 클리핑에 사용하는 카드 테두리 형태
const RoundedRectangleBorder _kCardShape = RoundedRectangleBorder(
  borderRadius: _kCardBorderRadius,
);

/// 카드 그림자 — 블랙 ~5 %, blur 12, offset (0, 4)
const List<BoxShadow> _kCardShadow = [
  BoxShadow(
    color: Color(0x0D000000), // 0x0D ≈ 5 % 불투명도
    blurRadius: 12,
    offset: Offset(0, 4),
  ),
];

/// chevron 아이콘 크기 (dp)
const double _kChevronSize = 20;

// ─────────────────────────────────────────────────────────────────────────────
// 위젯
// ─────────────────────────────────────────────────────────────────────────────

/// 일기 목록 항목 타일.
///
/// 흰 surface 카드 위에 날짜 eyebrow + 내용 미리보기(2줄 말줄임) + chevron을
/// 표시하는 순수 표현(Presentational) 위젯입니다.
///
/// **책임 분리**
/// - 좌우 수평 마진: 페이지(ListView, Padding 등)가 처리
/// - 항목 간 세로 간격: ListView.separated 의 separatorBuilder 가 처리
/// - 탭 동작(라우팅 등): [onTap] 콜백으로 외부에 위임
///
/// **사용 예시**
/// ```dart
/// DiaryListTile(
///   dateText: '6월 24일 (화)',
///   preview: diary.content,
///   onTap: () { /* TODO: 로직 연결 지점 */ },
/// )
/// ```
class DiaryListTile extends StatelessWidget {
  const DiaryListTile({
    super.key,
    required this.dateText,
    required this.preview,
    required this.onTap,
  });

  /// 상단 날짜 eyebrow 텍스트.
  /// 예: '6월 24일 (화)'
  final String dateText;

  /// 일기 내용 미리보기.
  /// 2줄을 초과하면 말줄임(…)으로 처리합니다.
  final String preview;

  /// 타일 전체 탭 콜백.
  // TODO: 로직 연결 지점 — go_router 로 일기 상세 화면(diary_detail_page) 푸시
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      // 그림자는 클리핑 외부에 있어야 하므로 Material 밖 DecoratedBox 에서 선언
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: _kCardBorderRadius,
        boxShadow: _kCardShadow,
      ),
      child: Material(
        // InkWell 잉크 효과가 카드 배경 위에 자연스럽게 올라오도록 투명 처리
        color: Colors.transparent,
        shape: _kCardShape,
        child: InkWell(
          onTap: onTap,
          customBorder: _kCardShape,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── 텍스트 영역 ─────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 날짜 eyebrow — accent 색, semibold
                      Text(
                        dateText,
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // 일기 내용 미리보기 — 최대 2줄, 말줄임
                      Text(
                        preview,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink,
                          height: 1.55, // 일기 느낌을 살리는 넉넉한 행간
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // ── chevron — 탭 가능성을 암시 ──────────────────
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.inkMuted,
                  size: _kChevronSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
