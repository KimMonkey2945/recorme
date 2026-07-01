import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// 작성 진입 시 사용자가 고르는 항목.
///
/// - [diary]: 오늘의 글(기록) 작성
/// - [resolution]: 작심삼일(3일 결심) 시작
enum WriteChoice { diary, resolution }

/// 작성 선택 바텀시트를 띄우고 사용자의 선택을 반환한다.
///
/// "글 작성"·"작심삼일 시작" 두 카드를 보여준다. 시트 밖 탭·백버튼으로 닫으면 null.
/// [allowResolution]이 false면(과거 날짜 등) 작심삼일 카드는 비활성(흐림) 처리하고
/// 안내 문구를 노출한다. 조작 CTA 맥락이므로 두 카드 모두 primary 톤을 쓴다.
Future<WriteChoice?> showWriteChoiceSheet(
  BuildContext context, {
  bool allowResolution = true,
}) {
  return showModalBottomSheet<WriteChoice>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.modal),
      ),
    ),
    builder: (sheetContext) => _WriteChoiceSheet(allowResolution: allowResolution),
  );
}

/// 바텀시트 본문 — 두 개의 선택 카드로 구성한다.
class _WriteChoiceSheet extends StatelessWidget {
  const _WriteChoiceSheet({required this.allowResolution});

  /// 작심삼일 카드 활성 여부.
  final bool allowResolution;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 그랩 핸들 ──
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '어떻게 기록할까요?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                letterSpacing: -0.02 * 18,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // ── 글 작성 ──
            _ChoiceCard(
              icon: Icons.edit_note,
              title: '글 작성',
              subtitle: '오늘 있었던 일을 기록해요',
              onTap: () => Navigator.of(context).pop(WriteChoice.diary),
            ),
            const SizedBox(height: AppSpacing.md),
            // ── 작심삼일 시작 (과거 날짜에는 비활성) ──
            _ChoiceCard(
              icon: Icons.flag_outlined,
              title: '작심삼일 시작',
              subtitle: allowResolution
                  ? '3일 도전으로 습관을 만들어요'
                  : '과거 날짜에는 시작할 수 없어요',
              enabled: allowResolution,
              onTap: allowResolution
                  ? () => Navigator.of(context).pop(WriteChoice.resolution)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 선택 카드 — 아이콘 원 + 제목/부제. primary 톤(조작 CTA).
///
/// [enabled]가 false면 전체를 흐리게(opacity 0.45) 표시하고 탭을 막는다.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.inkAlt,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 비활성이면 흐리게 표시(탭은 onTap=null로 이미 차단).
    return enabled ? card : Opacity(opacity: 0.45, child: card);
  }
}
