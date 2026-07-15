import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/api_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'providers/profile_providers.dart';

/// 프로필 조회 화면. GET /users/me 결과를 표시하고 수정/로그아웃 진입을 제공한다.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('프로필'),
          actions: [
            IconButton(
              tooltip: '로그아웃',
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(
          child: profile.when(
            loading: () => const LoadingView(message: '프로필을 불러오는 중...'),
            error: (err, _) => ErrorView(
              message:
                  err is Failure ? err.message : '프로필을 불러오지 못했어요',
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (user) => _ProfileBody(user: user),
          ),
        ),
      ),
    );
  }
}

/// 프로필 본문(아바타·닉네임·이메일·자기소개 + 수정 버튼).
class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          // 아바타(등록 이미지 또는 닉네임 이니셜)
          Center(
            child: ProfileAvatar(
              imageUrl: ApiConfig.resolveImageUrl(user.profileImageUrl),
              radius: 48,
              initial: ProfileAvatar.initialOf(user.nickname),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 닉네임 — 700 20px ink
          Text(
            user.nickname,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (user.email != null && user.email!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            // 이메일 — 13px inkMuted
            Text(
              user.email!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          // 자기소개 카드 — bgAlt 배경, 테두리 없음, radius 14
          _SectionCard(
            label: '자기소개',
            child: Text(
              (user.bio != null && user.bio!.isNotEmpty)
                  ? user.bio!
                  : '아직 자기소개가 없어요.',
              style: TextStyle(
                fontSize: 15,
                height: 1.6, // 시안 기준 행간
                color: (user.bio != null && user.bio!.isNotEmpty)
                    ? AppColors.ink
                    : AppColors.inkMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // 프로필 수정 버튼 — outlined (시안: hairline 테두리 + inkAlt)
          OutlinedButton.icon(
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('프로필 편집'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.inkAlt,
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: AppColors.hairline, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // 옷장 진입 — 캐릭터 꾸미기. 캐릭터 홈 탭(Task 029) 전까지의 임시 진입점.
          OutlinedButton.icon(
            onPressed: () => context.push('/wardrobe'),
            icon: const Icon(Icons.checkroom_outlined, size: 18),
            label: const Text('옷장'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.inkAlt,
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: AppColors.hairline, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // 친구 진입 — 친구 목록·요청·추가 화면으로.
          OutlinedButton.icon(
            onPressed: () => context.push('/friends'),
            icon: const Icon(Icons.people_alt_outlined, size: 18),
            label: const Text('친구'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.inkAlt,
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: AppColors.hairline, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 라벨 + 내용으로 구성된 카드.
/// 시안: bgAlt 배경, 테두리 없음, radius 14.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 15, // 시안 기준 15dp 수직 패딩
      ),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,       // surface → bgAlt
        borderRadius: BorderRadius.circular(14), // card(16) → 14
        // border 제거 (시안: no border)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelLarge?.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
