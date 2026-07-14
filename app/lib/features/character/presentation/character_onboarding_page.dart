import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/character.dart';
import 'providers/character_providers.dart';
import 'widgets/character_stage.dart';

/// 캐릭터 선택 온보딩 화면(셸 밖 풀스크린, `/onboarding/character`).
///
/// 인증됐지만 아직 캐릭터를 고르지 않은 사용자를 라우터 가드가 이리로 보낸다
/// (`myCharacterProvider`의 `character == null`이 신호).
///
/// 구성: 상단 원형 아이콘 → 헤드라인 → **캐러셀([PageView], 양옆 카드가 살짝 보이는 peek)**
/// → 페이지 도트 → 보조 문구 → 하단 "선택" 버튼.
/// 선택에 성공하면 기존 메인(`/`, 캘린더)으로 보낸다. 실패하면 스낵바만 띄우고
/// **온보딩에 그대로 머문다**(홈으로 새지 않는다).
class CharacterOnboardingPage extends ConsumerStatefulWidget {
  const CharacterOnboardingPage({super.key});

  /// 캐러셀 뷰포트 비율. 1 미만이라 좌우 카드가 살짝 보인다(peek).
  static const double viewportFraction = 0.78;

  @override
  ConsumerState<CharacterOnboardingPage> createState() =>
      _CharacterOnboardingPageState();
}

class _CharacterOnboardingPageState
    extends ConsumerState<CharacterOnboardingPage> {
  late final PageController _pageController = PageController(
    viewportFraction: CharacterOnboardingPage.viewportFraction,
  );

  /// 현재 중앙에 있는 카드 인덱스(도트 활성·선택 대상·idle 애니메이션 기준).
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// [index] 카드를 중앙으로 가져온다(옆 카드 탭·도트 탭).
  ///
  /// 드래그만으로는 전환이 되지 않는 입력 환경(마우스가 없는 접근성 도구 등)이 있고,
  /// 옆에 보이는 카드를 눌러 고르는 편이 터치에서도 자연스럽다.
  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// "선택" 제출. 성공 시 메인으로, 실패 시 스낵바 + 온보딩 유지.
  Future<void> _onSelect(List<Character> items) async {
    if (_currentPage < 0 || _currentPage >= items.length) return;
    final selected = items[_currentPage];

    try {
      await ref
          .read(selectCharacterControllerProvider.notifier)
          .submit(selected.code);
      if (!mounted) return;
      context.go('/');
    } on Object catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e is Failure ? e.message : '캐릭터를 선택하지 못했어요. 잠시 후 다시 시도해주세요.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final charactersAsync = ref.watch(charactersProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: charactersAsync.when(
          loading: () => const LoadingView(message: '캐릭터를 불러오는 중...'),
          error: (error, _) => ErrorView(
            message: error is Failure ? error.message : '캐릭터를 불러오지 못했어요.',
            onRetry: () => ref.invalidate(charactersProvider),
          ),
          data: (list) {
            if (list.items.isEmpty) {
              return ErrorView(
                message: '선택할 수 있는 캐릭터가 없어요.',
                onRetry: () => ref.invalidate(charactersProvider),
              );
            }
            return _buildContent(list.items);
          },
        ),
      ),
    );
  }

  Widget _buildContent(List<Character> items) {
    final textTheme = Theme.of(context).textTheme;
    // 중앙 카드(선택 대상). 스와이프 도중 인덱스가 범위를 벗어나지 않게 보정한다.
    final current = items[_currentPage.clamp(0, items.length - 1)];
    final isSubmitting = ref.watch(selectCharacterControllerProvider).isLoading;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.lg),

        // ── 상단 원형 캐릭터 아이콘(현재 카드의 얼굴) ──
        _CharacterBadge(assetPath: current.thumbnailUrl),
        const SizedBox(height: AppSpacing.lg),

        // ── 헤드라인 ──
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Text(
            '기억을 같이 만들어갈\n친구를 선택해주세요.',
            style: textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ── 캐러셀(peek) ──
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final isCenter = index == _currentPage;
              return AnimatedBuilder(
                animation: _pageController,
                // 카드 자체는 매 프레임 재생성할 필요가 없다 → child로 재사용.
                child: GestureDetector(
                  // 옆 카드를 탭하면 그 카드가 중앙으로 온다.
                  // 중앙 카드 탭은 무시한다 — 확정은 하단 "선택" 버튼이 담당한다.
                  onTap: isCenter ? null : () => _goToPage(index),
                  child: _CharacterCard(
                    character: items[index],
                    // 중앙 카드만 살아 움직인다(옆 카드는 정지 → 시선 집중).
                    isCenter: isCenter,
                    // 캐릭터마다 위상을 달리 줘 동작이 겹치지 않게 한다.
                    phase: index * 0.37,
                  ),
                ),
                builder: (context, child) {
                  // 중앙에서 멀어질수록 작고 흐리게(스와이프에 따라 연속 보간).
                  final page = (_pageController.hasClients &&
                          _pageController.position.haveDimensions)
                      ? (_pageController.page ?? _currentPage.toDouble())
                      : _currentPage.toDouble();
                  final t = (page - index).abs().clamp(0.0, 1.0);
                  return Opacity(
                    opacity: 1.0 - 0.55 * t,
                    child: Transform.scale(scale: 1.0 - 0.12 * t, child: child),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── 페이지 인디케이터 도트 ──
        _PageDots(
          count: items.length,
          activeIndex: _currentPage,
          onTap: _goToPage,
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── 보조 문구 ──
        Text(
          '캐릭터 꾸미기 메뉴에서\n마음에 드는 모습으로 변경할 수 있어요.',
          style: textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── 하단 고정 CTA ──
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            0,
            AppSpacing.screenHorizontal,
            AppSpacing.xl,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isSubmitting ? null : () => _onSelect(items),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.surface,
                      ),
                    )
                  : const Text('선택'),
            ),
          ),
        ),
      ],
    );
  }
}

/// 캐러셀 카드 1장: 캐릭터 무대 + 이름.
///
/// `Character.tagline`(성격 소개)은 백엔드가 계속 내려주지만 여기서는 렌더하지 않는다.
/// 화면을 캐릭터 자체에 집중시키기 위한 결정이다.
class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.isCenter,
    required this.phase,
  });

  final Character character;
  final bool isCenter;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        children: [
          Expanded(
            child: CharacterStage(
              assetPath: character.thumbnailUrl,
              animate: isCenter,
              phase: phase,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(character.nameKo, style: textTheme.headlineLarge),
        ],
      ),
    );
  }
}

/// 상단 원형 캐릭터 아이콘. 현재 카드의 얼굴이 보이도록 위쪽을 기준으로 크롭한다.
class _CharacterBadge extends StatelessWidget {
  const _CharacterBadge({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.paper,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline),
      ),
      child: ClipOval(
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          // 세로로 긴 전신 이미지라 위쪽(얼굴)을 보여준다.
          alignment: const Alignment(0, -0.72),
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.pets_rounded,
            color: AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// 페이지 인디케이터 도트(캐릭터 수만큼). 활성 도트는 길고 진하다.
/// 도트를 탭하면 해당 캐릭터로 이동한다.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.activeIndex,
    required this.onTap,
  });

  final int count;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            key: ValueKey('character-dot-$i'),
            onTap: () => onTap(i),
            // 도트 자체는 8px라 탭 타깃이 너무 작다 → 투명 패딩으로 넓힌다.
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == activeIndex ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == activeIndex
                      ? AppColors.primary
                      : AppColors.hairline,
                  borderRadius: AppRadius.chipBorderRadius,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
