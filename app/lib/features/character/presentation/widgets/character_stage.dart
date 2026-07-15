import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/equipment_item.dart';
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
/// ## 착용 아이템 합성 ([equipment])
/// - **착용형(HAT/OUTFIT/GLASSES/PROP)**: 캐릭터와 동일 프레임의 투명 PNG를
///   [IdleCharacterView]의 오버레이 레이어로 넘겨 **같은 메시 워프**에 태운다(z 오름차순).
///   `renderMeta.anchor/scale`은 이 방식에서는 쓰지 않는다(z만 사용) — 종이인형처럼
///   같은 도안 위에 겹치는 구조라 앵커 계산 자체가 필요 없다.
/// - **BACKGROUND**: 카드 전체를 덮는 배경(캐릭터 뒤).
/// - **ROOM_PROP**: 캐릭터 밖 소품 — `renderMeta.anchor/scale`(스테이지 정규화 좌표)로
///   정적 배치한다(캐릭터와 함께 움직이지 않는 것이 자연스럽다).
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
    this.equipment = const [],
  });

  /// 캐릭터 PNG 경로(서버 thumbnailUrl이 곧 이 경로다).
  final String assetPath;

  /// idle 애니메이션 재생 여부(캐러셀 중앙 카드만 true).
  final bool animate;

  /// 캐릭터별 위상(0~1). 두 캐릭터가 동시에 같은 동작을 하지 않게 한다.
  final double phase;

  /// 현재 착용/진열 중인 아이템(서버 상태 또는 옷장의 로컬 미리보기).
  final List<EquipmentItem> equipment;

  /// 캐릭터가 서 있는 바닥 그림자의 높이.
  static const double _groundHeight = 12;

  /// renderMeta가 없을 때 쓰는 슬롯별 기본 z.
  /// 겹침 규칙: 신발 위에 바지 밑단, 바지 위에 상의 밑단이 오도록
  /// SHOES(26) < BOTTOM(28) < OUTFIT(30) < GLASSES(35) < HAT(40).
  static const Map<String, int> _defaultZ = {
    'SHOES': 26,
    'BOTTOM': 28,
    'OUTFIT': 30,
    'GLASSES': 35,
    'HAT': 40,
    'PROP': 50,
  };

  /// 캐릭터 몸에 착용되는 슬롯(같은 메시 워프에 태우는 대상).
  static const Set<String> _wornSlots = {
    'HAT',
    'GLASSES',
    'OUTFIT',
    'BOTTOM',
    'SHOES',
    'PROP',
  };

  @override
  Widget build(BuildContext context) {
    final background = _backgroundItem();
    final roomProps = [
      for (final e in equipment)
        if (e.slot == 'ROOM_PROP') e,
    ];

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
            // ── 배경 아이템 ── 카드 전체를 덮는다(캐릭터·소품보다 뒤).
            if (background != null)
              Positioned.fill(
                child: Image.asset(
                  background.imageUrl,
                  fit: BoxFit.cover,
                  // 배경 로드 실패는 paper 카드 배경이 그대로 받는다.
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),

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

            // ── 방 소품 ── 스테이지 정규화 좌표(renderMeta)로 정적 배치(캐릭터 뒤).
            if (roomProps.isNotEmpty)
              Positioned.fill(child: _RoomPropLayer(props: roomProps)),

            // ── 캐릭터 + 착용 아이템(같은 메시 워프) ──
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
      overlayAssetPaths: _wornOverlayPaths(),
      animate: animate,
      phase: phase,
    );
  }

  EquipmentItem? _backgroundItem() {
    for (final e in equipment) {
      if (e.slot == 'BACKGROUND' && e.imageUrl.isNotEmpty) return e;
    }
    return null;
  }

  /// 착용형 아이템을 z 오름차순으로 정렬한 오버레이 경로 목록.
  List<String> _wornOverlayPaths() {
    final worn = [
      for (final e in equipment)
        if (_wornSlots.contains(e.slot) && e.imageUrl.isNotEmpty) e,
    ]..sort((a, b) => _zOf(a).compareTo(_zOf(b)));
    return [for (final e in worn) e.imageUrl];
  }

  int _zOf(EquipmentItem e) => e.renderMeta?.z ?? _defaultZ[e.slot] ?? 60;
}

/// 방 소품(ROOM_PROP)을 스테이지 정규화 좌표로 배치하는 레이어.
///
/// `renderMeta.anchorX/Y`(0~1, 좌상단 기준)가 소품의 **중심점**, `scale`은 스테이지 폭 대비
/// 소품 폭이다. 캐릭터 워프와 무관하게 고정 — 방 안 가구가 캐릭터 숨쉬기에 흔들리면 이상하다.
class _RoomPropLayer extends StatelessWidget {
  const _RoomPropLayer({required this.props});

  final List<EquipmentItem> props;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          children: [
            for (final prop in props) _positioned(prop, size),
          ],
        );
      },
    );
  }

  Widget _positioned(EquipmentItem prop, Size size) {
    final meta = prop.renderMeta;
    // 메타가 없으면 우하단 바닥 근처로 폴백(운영에서 크래시 금지).
    final anchorX = meta?.anchorX ?? 0.8;
    final anchorY = meta?.anchorY ?? 0.8;
    final scale = meta?.scale ?? 0.25;

    final w = size.width * scale;
    return Positioned(
      left: size.width * anchorX - w / 2,
      top: size.height * anchorY - w / 2,
      width: w,
      height: w,
      child: Image.asset(
        prop.imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }
}
