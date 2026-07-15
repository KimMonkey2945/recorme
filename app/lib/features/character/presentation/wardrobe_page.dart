import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/equipment_item.dart';
import '../domain/item_group.dart';
import '../domain/my_character.dart';
import 'providers/character_providers.dart';
import 'widgets/character_stage.dart';
import 'widgets/item_grid_tile.dart';
import 'widgets/locked_item_sheet.dart';
import 'widgets/wardrobe_save_bar.dart';
import 'widgets/wardrobe_slot_tabs.dart';

/// 옷장 화면(셸 밖 풀스크린, `/wardrobe`) — 종이인형 꾸미기의 본편.
///
/// 구성: 상단 캐릭터 미리보기([CharacterStage] — 로컬 선택이 **즉시** 반영된다)
/// → slot 탭 → 아이템 그리드(보유/미보유/선택 3상태) → 변경이 있을 때만 하단 저장 바.
///
/// ## 커밋 모델: 탭 = 로컬 미리보기, 저장 = 배치 커밋
/// `PUT /characters/me/equipment`는 **전체 스냅샷 교체**라 탭마다 커밋하면
/// 시행착오 중의 조합이 그대로 서버에 남는다. 그래서 탭은 [_provisional](로컬 상태)만
/// 바꾸고, "저장"에서 한 번에 커밋한다. "취소"는 서버 상태로 되돌린다.
///
/// 단일 슬롯(HAT/OUTFIT/GLASSES/PROP/BACKGROUND)은 탭 = 교체(같은 아이템 재탭 = 해제),
/// ROOM_PROP만 0~5 다중 토글이다.
class WardrobePage extends ConsumerStatefulWidget {
  const WardrobePage({super.key});

  /// ROOM_PROP 동시 진열 상한(백엔드 slotIndex 0~5와 동일).
  static const int maxRoomProps = 5;

  @override
  ConsumerState<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends ConsumerState<WardrobePage> {
  String _selectedSlot = 'HAT';

  /// 로컬 미리보기 착용 상태: slot → groupCode 목록(단일 슬롯은 0~1개).
  /// null이면 아직 서버 상태로 초기화되기 전이다(첫 데이터 도착 시 채운다).
  Map<String, List<String>>? _provisional;

  @override
  Widget build(BuildContext context) {
    final myAsync = ref.watch(myCharacterProvider);
    final itemsAsync = ref.watch(wardrobeItemsProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('옷장')),
      body: _buildBody(myAsync, itemsAsync),
    );
  }

  Widget _buildBody(
    AsyncValue<MyCharacter?> myAsync,
    AsyncValue<List<ItemGroup>> itemsAsync,
  ) {
    // 둘 중 하나라도 실패면 에러 + 재시도(둘 다 invalidate).
    final error = myAsync.hasError ? myAsync.error : itemsAsync.error;
    if (error != null) {
      return ErrorView(
        message: error is Failure ? error.message : '옷장을 불러오지 못했어요.',
        onRetry: () {
          ref.invalidate(myCharacterProvider);
          ref.invalidate(wardrobeItemsProvider);
        },
      );
    }

    final my = myAsync.value;
    final items = itemsAsync.value;
    if (my == null || items == null) {
      return const LoadingView(message: '옷장을 여는 중...');
    }

    final character = my.character;
    if (character == null) {
      // 가드가 온보딩으로 보내기 전의 찰나 — 빈 화면 대신 안내를 남긴다.
      return ErrorView(
        message: '먼저 캐릭터를 선택해주세요.',
        onRetry: () => ref.invalidate(myCharacterProvider),
      );
    }

    // 첫 데이터 도착 시 서버 착용 상태로 로컬 미리보기를 초기화한다.
    _provisional ??= _toSlotMap(my.equipment);
    final provisional = _provisional!;
    final serverMap = _toSlotMap(my.equipment);
    final dirty = !_slotMapEquals(provisional, serverMap);
    final saving = ref.watch(replaceEquipmentControllerProvider).isLoading;

    final slotItems = [
      for (final g in items)
        if (g.slot == _selectedSlot) g,
    ];
    final roomPropCount = provisional['ROOM_PROP']?.length ?? 0;

    return Column(
      children: [
        // ── 캐릭터 미리보기(로컬 선택 즉시 반영) ──
        SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: CharacterStage(
              assetPath: character.thumbnailUrl,
              equipment: _previewEquipment(items, provisional),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── slot 탭 ──
        WardrobeSlotTabs(
          selected: _selectedSlot,
          onSelected: (slot) => setState(() => _selectedSlot = slot),
        ),

        // ── ROOM_PROP 다중 진열 카운터 ──
        if (_selectedSlot == 'ROOM_PROP')
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '$roomPropCount / ${WardrobePage.maxRoomProps}개 진열 중',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.inkAlt),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),

        // ── 아이템 그리드 ──
        Expanded(
          child: slotItems.isEmpty
              ? Center(
                  child: Text(
                    '이 칸에 넣을 아이템이 아직 없어요.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    0,
                    AppSpacing.screenHorizontal,
                    AppSpacing.xl,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: slotItems.length,
                  itemBuilder: (context, index) {
                    final item = slotItems[index];
                    final codes = provisional[item.slot] ?? const [];
                    return ItemGridTile(
                      item: item,
                      selected: codes.contains(item.groupCode),
                      // 보유: 착용 토글(로컬 미리보기) / 미보유: 해금 조건 안내 시트.
                      onTap: item.owned
                          ? () => _onToggle(item)
                          : () => showLockedItemSheet(context, item),
                    );
                  },
                ),
        ),

        // ── 저장 바(dirty일 때만 올라온다) ──
        WardrobeSaveBar(
          visible: dirty,
          saving: saving,
          onSave: () => _onSave(provisional),
          onDiscard: () => setState(() => _provisional = serverMap),
        ),
      ],
    );
  }

  /// 아이템 탭: 로컬 미리보기 상태만 바꾼다(서버 커밋은 저장 바).
  void _onToggle(ItemGroup item) {
    final provisional = _provisional;
    if (provisional == null) return;

    final codes = List<String>.of(provisional[item.slot] ?? const []);
    if (item.slot == 'ROOM_PROP') {
      if (codes.contains(item.groupCode)) {
        codes.remove(item.groupCode);
      } else if (codes.length >= WardrobePage.maxRoomProps) {
        showAppSnackBar(
          context,
          '방 꾸미기는 ${WardrobePage.maxRoomProps}개까지 진열할 수 있어요.',
          isError: true,
        );
        return;
      } else {
        codes.add(item.groupCode);
      }
    } else {
      // 단일 슬롯: 같은 아이템 재탭 = 해제, 다른 아이템 탭 = 교체.
      final wasSelected = codes.contains(item.groupCode);
      codes.clear();
      if (!wasSelected) codes.add(item.groupCode);
    }

    setState(() => provisional[item.slot] = codes);
  }

  /// "저장": 로컬 상태를 배치 payload로 바꿔 한 번에 커밋한다.
  Future<void> _onSave(Map<String, List<String>> provisional) async {
    final payload = <EquipmentSelection>[
      for (final entry in provisional.entries)
        for (var i = 0; i < entry.value.length; i++)
          EquipmentSelection(
            slot: entry.key,
            slotIndex: i,
            groupCode: entry.value[i],
          ),
    ];

    try {
      await ref
          .read(replaceEquipmentControllerProvider.notifier)
          .submit(payload);
      if (!mounted) return;
      showAppSnackBar(context, '옷장을 저장했어요.');
    } on Object catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e is Failure ? e.message : '저장하지 못했어요. 잠시 후 다시 시도해주세요.',
        isError: true,
      );
    }
  }

  // ── 유틸 ────────────────────────────────────────────────────

  /// 서버 착용 목록 → slot 맵(slotIndex 순서 유지).
  static Map<String, List<String>> _toSlotMap(List<EquipmentItem> equipment) {
    final sorted = List.of(equipment)
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    final map = <String, List<String>>{};
    for (final e in sorted) {
      (map[e.slot] ??= []).add(e.groupCode);
    }
    return map;
  }

  static bool _slotMapEquals(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    // 빈 목록과 키 부재는 같은 상태다(해제된 슬롯).
    final keys = {...a.keys, ...b.keys};
    for (final key in keys) {
      final av = a[key] ?? const [];
      final bv = b[key] ?? const [];
      if (av.length != bv.length) return false;
      for (var i = 0; i < av.length; i++) {
        if (av[i] != bv[i]) return false;
      }
    }
    return true;
  }

  /// 로컬 미리보기 상태를 [CharacterStage]가 그릴 수 있는 착용 목록으로 바꾼다.
  /// 렌더 이미지·메타는 아이템 목록(내 캐릭터 기준으로 해석된 variant)에서 가져온다.
  List<EquipmentItem> _previewEquipment(
    List<ItemGroup> items,
    Map<String, List<String>> provisional,
  ) {
    final byCode = {for (final g in items) g.groupCode: g};
    final result = <EquipmentItem>[];
    for (final entry in provisional.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final group = byCode[entry.value[i]];
        if (group == null) continue;
        result.add(EquipmentItem(
          slot: entry.key,
          slotIndex: i,
          groupCode: group.groupCode,
          nameKo: group.nameKo,
          imageUrl: group.imageUrl,
          renderMeta: group.renderMeta,
        ));
      }
    }
    return result;
  }
}
