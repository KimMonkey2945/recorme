import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'providers/auth_provider.dart';

/// 로그인 화면. Supabase Auth 기반 카카오/구글 소셜 로그인.
///
/// 레이아웃 구조:
///   상단 — [_BrandSection] 아이콘 배지 + 워드마크 + 태그라인
///   하단 — [_LoginButtons] 카카오/구글 소셜 버튼
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  bool _loading = false;

  /// 소셜 로그인 액션을 실행한다.
  /// 성공 시 onAuthStateChange → 라우터 가드가 메인 화면으로 이동시킨다.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        // TODO: 로직 연결 지점 — 에러 유형별 메시지 분기 필요 시 e를 분석
        showAppSnackBar(context, '로그인에 실패했어요', isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(authControllerProvider.notifier);

    return Scaffold(
      // Foodu 톤 참고 — 화사한 웜 그라데이션 배경
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.bgGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
            ),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상단 여백 — 브랜드 영역을 화면 중앙 위쪽에 자연스럽게 배치
              const Spacer(flex: 3),
              const _BrandSection(),
              // 브랜드↔버튼 사이 여백 — 버튼이 하단에 머무르도록 더 크게 배분
              const Spacer(flex: 4),
              // 하단 로그인 버튼 영역
              _LoginButtons(
                loading: _loading,
                onKakaoTap: () => _run(controller.signInWithKakao),
                onGoogleTap: () => _run(controller.signInWithGoogle),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ), // Column
        ), // Padding
      ), // SafeArea
    ), // Container
    ); // Scaffold
  }
}

// ─────────────────────────────────────────────────────────────
// 브랜드 영역
// ─────────────────────────────────────────────────────────────

/// accentSoft 배경 아이콘 배지 + 워드마크 'record' + 태그라인으로 구성된 브랜드 섹션.
class _BrandSection extends StatelessWidget {
  const _BrandSection();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 앱 정체성 시각 요소 — accentSoft 배경 + 펜 아이콘 1개 (화면 비중 확대)
        Container(
          width: 124,
          height: 124,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.card + 8),
          ),
          child: const Icon(
            Icons.edit_rounded,
            size: 60,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // 워드마크 — displayLarge 베이스(w700, ink)에 크기 확대
        Text(
          'recorme',
          style: textTheme.displayLarge?.copyWith(
            fontSize: 54,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // 태그라인 — inkMuted 보조 텍스트
        Text(
          '하루를 글로 기록하세요',
          style: textTheme.titleMedium?.copyWith(
            color: AppColors.inkMuted,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 로그인 버튼 영역
// ─────────────────────────────────────────────────────────────

/// 카카오/구글 버튼 컨테이너.
///
/// [loading]이 true이면 두 버튼을 모두 비활성화하고
/// 고정 높이 영역(24dp)에 작은 인디케이터를 표시해 레이아웃 이동을 방지한다.
class _LoginButtons extends StatelessWidget {
  const _LoginButtons({
    required this.loading,
    required this.onKakaoTap,
    required this.onGoogleTap,
  });

  final bool loading;
  final VoidCallback onKakaoTap;
  final VoidCallback onGoogleTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 로딩 인디케이터 — SizedBox 고정 높이로 레이아웃 점프 방지
        SizedBox(
          height: 24,
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: AppSpacing.xs),
        // 카카오 버튼
        _KakaoButton(onTap: loading ? null : onKakaoTap),
        const SizedBox(height: AppSpacing.sm),
        // 구글 버튼
        _GoogleButton(onTap: loading ? null : onGoogleTap),
      ],
    );
  }
}

/// 카카오 브랜드 버튼.
///
/// 배경 #FEE500, 텍스트 #191600 — Kakao Design System 지정 고정값.
/// (브랜드 가이드 예외 허용: 앱 내 디자인 토큰 대신 브랜드 컬러 직접 사용)
class _KakaoButton extends StatelessWidget {
  const _KakaoButton({this.onTap});

  final VoidCallback? onTap;

  // 카카오 브랜드 컬러 — Kakao Design System 고정값
  static const Color _kakaoYellow = Color(0xFFFEE500);
  static const Color _kakaoLabel = Color(0xFF191600);
  // 비활성 색상 — 알파값 조정 (0x7F ≈ 50%, 0x66 ≈ 40%)
  static const Color _kakaoYellowDisabled = Color(0x7FFEE500);
  static const Color _kakaoLabelDisabled = Color(0x66191600);

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _kakaoYellow,
        foregroundColor: _kakaoLabel,
        disabledBackgroundColor: _kakaoYellowDisabled,
        disabledForegroundColor: _kakaoLabelDisabled,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        // color 미지정 → foregroundColor/disabledForegroundColor 자동 상속
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      // 아이콘은 좌측 정렬, 라벨은 가운데 정렬 (사진 레이아웃)
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            // 카카오톡 말풍선 아이콘 (foregroundColor 상속 → 다크)
            child: Icon(Icons.chat_bubble, size: 20),
          ),
          Text('카카오 로그인'),
        ],
      ),
    );
  }
}

/// 구글 OutlinedButton.
///
/// 흰 배경 + hairline 테두리. 공식 멀티컬러 'G' 로고(SVG 에셋)로 브랜드 표현.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        disabledForegroundColor: AppColors.inkMuted,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        // 테마 기본 accent 테두리 대신 hairline 테두리로 오버라이드
        side: const BorderSide(color: AppColors.hairline, width: 1.5),
        // color 미지정 → foregroundColor/disabledForegroundColor 자동 상속
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      // 아이콘은 좌측 정렬, 라벨은 가운데 정렬 (사진 레이아웃)
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            // 공식 멀티컬러 구글 G 로고. 비활성 시 살짝 흐리게.
            child: Opacity(
              opacity: onTap != null ? 1.0 : 0.4,
              child: SvgPicture.asset(
                'assets/icons/google_g.svg',
                width: 20,
                height: 20,
              ),
            ),
          ),
          // color 미지정 → 버튼 foregroundColor/disabledForegroundColor 상속
          const Text('Google 로그인'),
        ],
      ),
    );
  }
}
