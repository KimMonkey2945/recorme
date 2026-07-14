import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'idle_character_view.dart';

/// 캐릭터를 올려두는 "무대" — 배경 카드이자 렌더러 배선이다.
///
/// ## 렌더러: 통짜 PNG + 메시 워프 ([IdleCharacterView])
///
/// **파츠 조립과 Rive를 둘 다 시도했다가 되돌아왔다.** 기록을 남긴다:
///
/// - **Rive**: 메시 변형·IK가 이 캐릭터엔 필요 없고, `.riv` 런타임 export가 유료이며,
///   리깅이 GUI 수작업이라 코드로 전달되지 않는다 → 미채택.
/// - **파츠 조립(머리·몸통·팔·다리 낱장을 관절로 엮기)**: 구현은 됐지만 **결과가 조각나 보였다.**
///   파츠들이 같은 3D 모델을 분해한 게 아니라 **각각 따로 생성된 이미지**라, 눈 간격(101 vs 117),
///   몸통 색, 팔 소켓과 소매 구멍 크기가 서로 맞지 않는다. 좌표를 고칠 때마다 다른 곳이 틀어졌다.
///   **이건 코드로 수렴하지 않는다 — 파츠를 다시 그려야 풀리는 문제다.**
///
/// → 통짜 PNG는 그 자체로 완성돼 있고, 메시 워프로 충분히 살아 움직인다. **눈 깜빡임은 포기했다**
/// (통짜 이미지로는 눈을 감길 수 없다). 눈 깜빡임 하나를 위해 캐릭터가 조각나 보이는 건 손해다.
/// 자세한 경위는 `tasks/031-app-parts-character-renderer.md`.
///
/// ## 배경 카드 구성
/// 캐릭터를 화면 배경에 그냥 얹지 않고 [AppColors.paper] 카드 위에 올린다.
/// 바닥 그림자(타원)는 캐릭터 발밑에 깔아 접지감을 준다.
class CharacterStage extends StatelessWidget {
  const CharacterStage({
    super.key,
    required this.assetPath,
    this.animate = true,
    this.phase = 0,
  });

  /// 캐릭터 PNG 경로(서버 thumbnailUrl이 곧 이 경로다).
  final String assetPath;

  /// idle 애니메이션 재생 여부(캐러셀 중앙 카드만 true).
  final bool animate;

  /// 캐릭터별 위상(0~1). 두 캐릭터가 동시에 같은 동작을 하지 않게 한다.
  final double phase;

  /// 캐릭터가 서 있는 바닥 그림자의 높이.
  static const double _groundHeight = 12;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // 불투명 PNG가 카드 모서리를 삐져나오지 않도록 카드 반경으로 클립한다.
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // 크림색 PNG 배경과 이질감이 없는 따뜻한 종이 톤.
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // ── 바닥 그림자(타원) ── 캐릭터 이미지 아래 바깥에 깔린다.
            Positioned(
              bottom: AppSpacing.lg,
              child: Container(
                width: 96,
                height: _groundHeight,
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(48, _groundHeight / 2),
                  ),
                ),
              ),
            ),

            // ── 캐릭터 ──
            Positioned.fill(
              child: Padding(
                // 하단 여백: 이미지 밑변이 바닥 그림자 위에 서도록 띄운다.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                child: _buildRenderer(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRenderer() {
    return IdleCharacterView(
      assetPath: assetPath,
      animate: animate,
      phase: phase,
    );
  }
}
