import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'idle_character_view.dart';

/// `--dart-define=USE_RIVE=true`면 Rive 렌더러 경로를 켠다(기본 false).
///
/// 웹에서는 항상 비-Rive 경로를 쓴다(아래 [CharacterStage] 참고).
const bool useRive = bool.fromEnvironment('USE_RIVE');

/// 캐릭터를 올려두는 "무대" — **렌더러 스위치**이자 배경 카드다.
///
/// ## 렌더러 스위치
/// - `USE_RIVE=true` + 네이티브: Rive 아트보드 렌더러(Task 031에서 드롭인).
/// - 그 외(기본·웹): [IdleCharacterView] — PNG + 절차적 idle 애니메이션.
///
/// 현재 `.riv` 아트보드가 **존재하지 않으므로** Rive 분기는 실제 위젯을 만들지 않고
/// PNG 렌더러로 폴백한다. `rive` 패키지도 아직 pubspec에 넣지 않는다.
///
/// ## 배경 카드 구성 (중요)
/// 캐릭터 PNG는 현재 **배경이 불투명한 크림색**이다(투명 PNG로 교체 예정).
/// 그래서 캐릭터를 화면 배경에 그냥 얹지 않고, 크림색과 가까운 [AppColors.paper]
/// 카드 위에 올려 흰 박스가 튀지 않게 한다. 바닥 그림자(타원)는 이미지 아래쪽
/// 바깥에 그려 불투명 PNG에 가려지지 않게 배치한다.
/// → 나중에 투명 PNG로 파일만 교체해도 구도가 그대로 자연스럽게 동작한다.
class CharacterStage extends StatelessWidget {
  const CharacterStage({
    super.key,
    required this.assetPath,
    this.animate = true,
    this.phase = 0,
  });

  /// 캐릭터 이미지 에셋 경로(서버 thumbnailUrl이 곧 이 경로다).
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

  /// 렌더러 선택. 웹이면 무조건 비-Rive 경로다.
  Widget _buildRenderer() {
    final riveEnabled = useRive && !kIsWeb;

    if (riveEnabled) {
      // ──────────────────────────────────────────────────────────────
      // TODO(Task 031): 여기에 Rive 렌더러를 드롭인한다.
      //
      //   // pubspec: rive: ^0.14.0-dev.6
      //   // main(): WidgetsFlutterBinding.ensureInitialized(); await RiveNative.init();
      //   final file = await File.asset('assets/rive/monkey.riv', riveFactory: Factory.rive);
      //   final controller = RiveWidgetController(
      //     file,
      //     stateMachineSelector: StateMachineSelector.byName('Idle'),
      //   );
      //   return RiveWidget(controller: controller, fit: Fit.contain);
      //
      // 아트보드명은 MyCharacter.riveArtboard(서버 제공, 예: 'monkey')를 쓴다.
      // .riv 로드는 비동기라 StatefulWidget + FutureBuilder로 감싸고,
      // 로드 실패 시에는 아래 PNG 렌더러로 폴백해야 한다.
      // ──────────────────────────────────────────────────────────────
      //
      // 아직 .riv 아트보드가 없으므로 지금은 PNG idle 렌더러로 폴백한다.
    }

    return IdleCharacterView(
      assetPath: assetPath,
      animate: animate,
      phase: phase,
    );
  }
}
