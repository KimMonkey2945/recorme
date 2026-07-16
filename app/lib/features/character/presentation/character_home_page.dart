import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/my_character.dart';
import 'providers/character_providers.dart';
import 'widgets/character_stage.dart';

/// 캐릭터 홈(하단 탭 index 0, `/`) — 로그인 후 가장 먼저 보이는 몰입형 방.
///
/// 구성(위→아래): 상태바(Lv·경험치 게이지·코인·보상 배지) → 중앙 캐릭터 대형
/// ([CharacterStage] — 배경·소품·착용 아이템까지 서버 상태 그대로) → 이름·소개 패널
/// → 옷장 진입 버튼. 미션·상점·기록 CTA는 이후 Task(028·030) 범위다.
///
/// 상태는 [myCharacterProvider](라우터 온보딩 가드가 구독하는 단일 소스)를 그대로 watch한다.
/// 옷장에서 착용을 저장하면 [ReplaceEquipmentController]가 이 provider를 invalidate하므로
/// 홈에 돌아오면 자동으로 갱신된다. 소개 문구는 [charactersProvider](온보딩 캐러셀과 공유)에서
/// 코드로 찾아 쓰되, 아직 로드 전이거나 실패하면 문구만 생략한다(홈은 그래도 성립).
class CharacterHomePage extends ConsumerStatefulWidget {
  const CharacterHomePage({super.key});

  @override
  ConsumerState<CharacterHomePage> createState() => _CharacterHomePageState();
}

class _CharacterHomePageState extends ConsumerState<CharacterHomePage> {
  @override
  void initState() {
    super.initState();
    // 홈 진입 시 출석 도장(하루 1회). 첫 프레임 이후에 호출해 build 중 provider 변경을 피한다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAttendance());
  }

  /// 출석 적립. 이번에 적립됐으면 잔잔한 스낵바로 알린다(실패는 조용히 무시 — 홈을 막지 않는다).
  Future<void> _markAttendance() async {
    final result = await ref.read(attendanceControllerProvider.notifier).mark();
    if (!mounted) return;
    if (result != null && result.granted) {
      showAppSnackBar(context, '출석 완료! 코인 +${result.coin}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final myAsync = ref.watch(myCharacterProvider);

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: myAsync.when(
            loading: () => const LoadingView(message: '캐릭터를 불러오는 중...'),
            error: (err, _) => ErrorView(
              message: err is Failure ? err.message : '캐릭터를 불러오지 못했어요.',
              onRetry: () => ref.invalidate(myCharacterProvider),
            ),
            data: (my) {
              final character = my?.character;
              // 미인증(null) 또는 미선택(character==null)이면 라우터 가드가
              // 로그인/온보딩으로 보내는 중이다 — 빈 화면으로 그 찰나를 넘긴다.
              if (my == null || character == null) {
                return const SizedBox.shrink();
              }
              return _HomeBody(
                my: my,
                character: character,
                tagline: _taglineFor(character.code),
                onRefresh: () async => ref.invalidate(myCharacterProvider),
                onRewardsTap: () => context.push('/rewards'),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 선택 캐릭터의 소개 문구를 캐러셀 목록에서 찾는다(미로드/미발견이면 null).
  String? _taglineFor(String code) {
    final list = ref.watch(charactersProvider).asData?.value;
    if (list == null) return null;
    for (final c in list.items) {
      if (c.code == code) return c.tagline;
    }
    return null;
  }
}

/// 홈 본문 — 상태바·캐릭터·이름/소개·옷장 버튼을 세로로 쌓고 당겨서 새로고침한다.
class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.my,
    required this.character,
    required this.tagline,
    required this.onRefresh,
    required this.onRewardsTap,
  });

  final MyCharacter my;
  final SelectedCharacter character;
  final String? tagline;
  final Future<void> Function() onRefresh;
  final VoidCallback onRewardsTap;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 화면을 꽉 채우되(몰입형), 당겨서 새로고침이 가능하도록 스크롤 뷰 안에 담는다.
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    AppSpacing.lg,
                    AppSpacing.screenHorizontal,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusBar(
                        coinBalance: my.coinBalance,
                        unackedRewardCount: my.unackedRewardCount,
                        onRewardsTap: onRewardsTap,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // 중앙 캐릭터 — 남는 세로 공간을 모두 차지한다.
                      Expanded(
                        child: CharacterStage(
                          assetPath: character.thumbnailUrl,
                          equipment: my.equipment,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _NamePanel(name: character.nameKo, tagline: tagline),
                      const SizedBox(height: AppSpacing.lg),
                      // 옷장 진입 — 캐릭터 홈의 유일한 주 액션(이번 범위).
                      FilledButton.icon(
                        onPressed: () => context.push('/wardrobe'),
                        icon: const Icon(Icons.checkroom, size: 20),
                        label: const Text('옷장'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 상단 상태바 — 코인 · 미확인 보상 배지(우측 정렬).
///
/// 레벨/경험치는 보상 재설계로 제거됐다 — 성장은 코인·미션 해금으로만 표현한다.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.coinBalance,
    required this.unackedRewardCount,
    required this.onRewardsTap,
  });

  final int coinBalance;
  final int unackedRewardCount;
  final VoidCallback onRewardsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // ── 코인 ──
        _CoinChip(balance: coinBalance),
        const SizedBox(width: AppSpacing.md),
        // ── 미확인 보상 배지(탭 → 보상함). 개수>0일 때만 숫자 표시 ──
        IconButton(
          onPressed: onRewardsTap,
          tooltip: '보상함',
          icon: Badge(
            isLabelVisible: unackedRewardCount > 0,
            label: Text('$unackedRewardCount'),
            child: const Icon(
              Icons.card_giftcard_outlined,
              color: AppColors.inkAlt,
            ),
          ),
        ),
      ],
    );
  }
}

/// 코인 잔액 칩.
class _CoinChip extends StatelessWidget {
  const _CoinChip({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.monetization_on, color: AppColors.warning, size: 20),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '$balance',
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

/// 이름 + 소개 패널 — 이름 크게, 소개는 옅은 카드(문구 없으면 카드 생략).
class _NamePanel extends StatelessWidget {
  const _NamePanel({required this.name, required this.tagline});

  final String name;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (tagline != null && tagline!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.bgAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              tagline!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.inkAlt,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
