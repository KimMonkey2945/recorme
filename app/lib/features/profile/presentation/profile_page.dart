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
    final textTheme = Theme.of(context).textTheme;

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
          // 닉네임
          Text(
            user.nickname,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall,
          ),
          if (user.email != null && user.email!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              user.email!,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          // 자기소개 카드
          _SectionCard(
            label: '자기소개',
            child: Text(
              (user.bio != null && user.bio!.isNotEmpty)
                  ? user.bio!
                  : '아직 자기소개가 없어요.',
              style: textTheme.bodyMedium?.copyWith(
                color: (user.bio != null && user.bio!.isNotEmpty)
                    ? AppColors.ink
                    : AppColors.inkMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('프로필 수정'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
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

/// 라벨 + 내용으로 구성된 surface 카드.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
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
