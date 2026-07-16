import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/equipment_item.dart';
import '../../domain/my_character.dart';
import '../../domain/reward.dart';
import 'character_speech_bubble.dart';
import 'character_stage.dart';

/// 확정 직후 리액션 오버레이(F031) — 대기 없이 내 캐릭터가 등장해 한 줄 반응한다.
///
/// 기록을 확정('오늘을 기억하기')하면 상세 화면 위에 이 오버레이가 뜬다. 감정 분석을 끈(Task 024)
/// 뒤 확정은 즉시 DONE 이라 **폴링·로딩 스피너·영상이 없다** — 리액션 지연 0.
///
/// - **대사 1줄은 항상** 표시한다(획득이 없어도, 서버 대사가 없으면 캐릭터별 기본 대사로 대체 — 빈손 금지).
/// - 코인을 벌었으면 획득 카드를 함께 보여 준다.
/// - 아무 곳이나 탭하거나 '확인'을 누르면 [onDismiss] — 호출부가 ack(배지 감소)하고 오버레이를 닫는다.
///
/// 캐릭터는 홈과 **동일한 [CharacterStage]** 로 그린다(착용 아이템까지 그대로).
class ReactionOverlay extends StatelessWidget {
  const ReactionOverlay({
    super.key,
    required this.character,
    required this.equipment,
    required this.reaction,
    required this.onDismiss,
  });

  /// 등장할 내 캐릭터(스테이지 렌더용).
  final SelectedCharacter character;

  /// 현재 착용 스냅샷(스테이지에 함께 합성).
  final List<EquipmentItem> equipment;

  /// 서버 리액션(대사·코인). null 이면(아직 미생성) 기본 대사로 대체한다.
  final Reward? reaction;

  /// 닫기 콜백(ack + 오버레이 제거는 호출부가 수행).
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final line = _resolveLine();
    final coin = reaction?.coinDelta ?? 0;

    return Positioned.fill(
      child: GestureDetector(
        // 배경 아무 곳이나 탭하면 닫힌다.
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: AppColors.ink.withValues(alpha: 0.55),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CharacterSpeechBubble(text: line),
                  const SizedBox(height: AppSpacing.md),
                  // 캐릭터 무대 — 홈과 동일 렌더러. 오버레이라 크기를 고정한다
                  // (가운데 정렬 Column 안에서 width 가 무한이 되지 않게 명시적으로 준다).
                  SizedBox(
                    width: 220,
                    height: 260,
                    child: CharacterStage(
                      assetPath: character.thumbnailUrl,
                      equipment: equipment,
                    ),
                  ),
                  if (coin > 0) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _CoinRewardCard(coin: coin),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: onDismiss,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 48),
                    ),
                    child: const Text('확인'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 표시할 대사 — 서버 대사가 있으면 그대로, 없으면 캐릭터 성격별 기본 대사(빈손 금지).
  String _resolveLine() {
    final serverLine = reaction?.line;
    if (serverLine != null && serverLine.isNotEmpty) return serverLine;
    // 원숭이는 느긋한 말투, 레서판다는 애쓰는 말투로 성격 대비를 유지한다.
    return character.code == 'RED_PANDA'
        ? '오늘도 해냈네요! 이 기세로 내일도 꼭 같이 써요.'
        : '오늘도 한 줄 남겼네. 천천히 해도 다 남더라.';
  }
}

/// 코인 획득 카드 — 이번 확정으로 번 코인을 강조한다.
class _CoinRewardCard extends StatelessWidget {
  const _CoinRewardCard({required this.coin});

  final int coin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on, color: AppColors.warning, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '코인 +$coin',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
