import 'package:flutter/material.dart';

import 'package:record/core/config/api_config.dart';
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

/// 기록 목록 항목 타일.
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
    this.thumbnailUrl,
    this.imageCount = 0,
    this.isDraft = false,
  });

  /// 상단 날짜 eyebrow 텍스트.
  /// 예: '6월 24일 (화)'
  final String dateText;

  /// 기록 내용 미리보기.
  /// 2줄을 초과하면 말줄임(…)으로 처리합니다.
  final String preview;

  /// 타일 전체 탭 콜백.
  final VoidCallback onTap;

  /// 대표 이미지 경로(없으면 썸네일 미표시). 상대 경로는 내부에서 절대화한다.
  final String? thumbnailUrl;

  /// 첨부 이미지 개수(1장 초과면 썸네일에 개수 배지 표시).
  final int imageCount;

  /// 임시 저장(DRAFT) 여부. true이면 날짜 옆에 '작성 중' 배지를 표시한다.
  final bool isDraft;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final resolvedThumb = ApiConfig.resolveImageUrl(thumbnailUrl);

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
                // ── 대표 이미지 썸네일(있을 때만) ───────────────
                if (resolvedThumb != null) ...[
                  _ListThumbnail(url: resolvedThumb, imageCount: imageCount),
                  const SizedBox(width: AppSpacing.md),
                ],
                // ── 텍스트 영역 ─────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 날짜 eyebrow + DRAFT '작성 중' 배지(감정색 사용 안 함).
                      Row(
                        children: [
                          Text(
                            dateText,
                            style: textTheme.labelMedium?.copyWith(
                              color: AppColors.inkAlt, // 시안: date eyebrow inkAlt
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (isDraft) ...[
                            const SizedBox(width: AppSpacing.xs),
                            _DraftBadge(textTheme: textTheme),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // 기록 내용 미리보기 — 최대 2줄, 말줄임
                      Text(
                        preview,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkAlt, // 시안: preview inkAlt
                          height: 1.55,
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

// ─────────────────────────────────────────────────────────────────────────────
// 목록 대표 이미지 썸네일
// ─────────────────────────────────────────────────────────────────────────────

/// 56×56 둥근 썸네일. [imageCount]가 2 이상이면 우하단에 개수 배지를 얹는다.
class _ListThumbnail extends StatelessWidget {
  const _ListThumbnail({required this.url, required this.imageCount});

  /// 절대 URL(상위에서 resolveImageUrl 적용 후 전달).
  final String url;
  final int imageCount;

  static const double _size = 56;

  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(AppRadius.sm));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: _radius,
            child: Image.network(
              url,
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              // 로딩 전/실패 시 hairline 플레이스홀더로 레이아웃 점프 방지.
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: AppColors.hairline,
                child: SizedBox.square(
                  dimension: _size,
                  child: Icon(
                    Icons.image_outlined,
                    color: AppColors.inkMuted,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          // 사진이 여러 장이면 개수 배지 표시.
          if (imageCount > 1)
            Positioned(
              right: 3,
              bottom: 3,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  // AppColors.ink(0xFF232228) 80% 알파 → 0xCC232228
                  color: Color(0xCC232228),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  child: Text(
                    '$imageCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.surface,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAFT '작성 중' 배지
// ─────────────────────────────────────────────────────────────────────────────

/// DRAFT 기록 타일의 날짜 eyebrow 옆에 표시하는 중립 회색 배지.
///
/// 감정 분석 결과 색(accent)을 사용하지 않고 [AppColors.hairline] 배경 + [AppColors.inkMuted]
/// 텍스트로 중립적으로 표시해 아직 확정되지 않은 상태임을 나타낸다.
class _DraftBadge extends StatelessWidget {
  const _DraftBadge({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.hairline,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          '작성 중',
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w500,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}
