// CharacterStage 착용 아이템 합성 테스트.
// - 착용형(HAT/OUTFIT/GLASSES/PROP)은 z 오름차순으로 IdleCharacterView 오버레이에 전달된다.
// - BACKGROUND는 카드 배경 이미지로, ROOM_PROP은 정적 배치 이미지로 렌더된다.
// - renderMeta가 없어도(폴백 z·앵커) 예외 없이 렌더된다.
//
// 테스트 환경에는 raw 이미지 디코딩이 없어 메시 렌더 대신 폴백 경로를 타지만,
// "무엇을 어떤 순서로 그리라고 배선했는가"는 위젯 속성으로 검증할 수 있다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/character/domain/equipment_item.dart';
import 'package:record/features/character/domain/render_meta.dart';
import 'package:record/features/character/presentation/widgets/character_stage.dart';
import 'package:record/features/character/presentation/widgets/idle_character_view.dart';

Widget _wrap(List<EquipmentItem> equipment) => MaterialApp(
      home: Scaffold(
        body: CharacterStage(
          assetPath: 'assets/characters/monkey.png',
          animate: false,
          equipment: equipment,
        ),
      ),
    );

const _hat = EquipmentItem(
  slot: 'HAT',
  slotIndex: 0,
  groupCode: 'HAT_CAP_EMIS',
  nameKo: '이미스 볼캡',
  imageUrl: 'assets/items/hat_cap_emis_monkey.png',
  renderMeta: RenderMeta(anchorX: 0.5, anchorY: 0.18, scale: 0.42, z: 40),
);

const _outfit = EquipmentItem(
  slot: 'OUTFIT',
  slotIndex: 0,
  groupCode: 'OUTFIT_BASIC_TEE',
  nameKo: '기본 흰 티셔츠',
  imageUrl: 'assets/items/outfit_basic_tee_monkey.png',
  renderMeta: RenderMeta(anchorX: 0.5, anchorY: 0.55, scale: 0.60, z: 30),
);

const _background = EquipmentItem(
  slot: 'BACKGROUND',
  slotIndex: 0,
  groupCode: 'BG_COZY_ROOM',
  nameKo: '아늑한 방',
  imageUrl: 'assets/items/bg_cozy_room.png',
  renderMeta: RenderMeta(anchorX: 0.5, anchorY: 0.5, scale: 1.0, z: 0),
);

const _plant = EquipmentItem(
  slot: 'ROOM_PROP',
  slotIndex: 0,
  groupCode: 'ROOM_PROP_PLANT',
  nameKo: '작은 화분',
  imageUrl: 'assets/items/room_prop_plant.png',
  renderMeta: RenderMeta(anchorX: 0.82, anchorY: 0.78, scale: 0.30, z: 10),
);

void main() {
  setUp(() => IdleCharacterView.debugDisableIdleAnimation = true);
  tearDown(() => IdleCharacterView.debugDisableIdleAnimation = false);

  IdleCharacterView rendererOf(WidgetTester tester) =>
      tester.widget<IdleCharacterView>(find.byType(IdleCharacterView));

  testWidgets('착용 아이템이 없으면 오버레이도 비어 있다', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();

    expect(rendererOf(tester).overlayAssetPaths, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('착용형 아이템은 z 오름차순으로 오버레이에 전달된다(옷 30 → 모자 40)',
      (tester) async {
    // 일부러 모자를 먼저 넣어 정렬을 검증한다.
    await tester.pumpWidget(_wrap(const [_hat, _outfit]));
    await tester.pumpAndSettle();

    expect(rendererOf(tester).overlayAssetPaths, const [
      'assets/items/outfit_basic_tee_monkey.png',
      'assets/items/hat_cap_emis_monkey.png',
    ]);
  });

  testWidgets('BACKGROUND·ROOM_PROP은 오버레이가 아니라 스테이지 레이어로 렌더된다',
      (tester) async {
    await tester.pumpWidget(_wrap(const [_background, _plant, _hat]));
    await tester.pumpAndSettle();

    // 캐릭터 몸에 얹는 오버레이는 모자뿐이다.
    expect(rendererOf(tester).overlayAssetPaths, const [
      'assets/items/hat_cap_emis_monkey.png',
    ]);

    // 배경·소품은 Image 위젯으로 스테이지에 깔린다.
    final imageAssets = tester
        .widgetList<Image>(find.byType(Image))
        .map((w) => (w.image as AssetImage).assetName)
        .toList();
    expect(imageAssets, contains('assets/items/bg_cozy_room.png'));
    expect(imageAssets, contains('assets/items/room_prop_plant.png'));
  });

  testWidgets('renderMeta가 없어도 폴백(슬롯 기본 z·기본 앵커)으로 예외 없이 렌더된다',
      (tester) async {
    const bareHat = EquipmentItem(
      slot: 'HAT',
      slotIndex: 0,
      groupCode: 'HAT_CAP_EMIS',
      nameKo: '이미스 볼캡',
      imageUrl: 'assets/items/hat_cap_emis_monkey.png',
    );
    const bareProp = EquipmentItem(
      slot: 'ROOM_PROP',
      slotIndex: 0,
      groupCode: 'ROOM_PROP_PLANT',
      nameKo: '작은 화분',
      imageUrl: 'assets/items/room_prop_plant.png',
    );

    await tester.pumpWidget(_wrap(const [bareHat, bareProp, _outfit]));
    await tester.pumpAndSettle();

    // 기본 z: OUTFIT 30 < HAT 40 순서가 유지된다.
    expect(rendererOf(tester).overlayAssetPaths, const [
      'assets/items/outfit_basic_tee_monkey.png',
      'assets/items/hat_cap_emis_monkey.png',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('imageUrl이 빈 아이템은 조용히 건너뛴다', (tester) async {
    const broken = EquipmentItem(
      slot: 'HAT',
      slotIndex: 0,
      groupCode: 'HAT_BROKEN',
      nameKo: '이미지 없는 모자',
      imageUrl: '',
    );

    await tester.pumpWidget(_wrap(const [broken]));
    await tester.pumpAndSettle();

    expect(rendererOf(tester).overlayAssetPaths, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
