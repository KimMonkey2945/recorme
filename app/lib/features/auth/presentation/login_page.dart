import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'providers/auth_provider.dart';
import 'widgets/auth_form_fields.dart';

/// 로그인 화면. 이메일/비밀번호 로그인 + 카카오/구글 소셜 로그인.
///
/// 레이아웃 구조:
///   상단 — [_BrandSection] 아이콘 배지 + 워드마크 + 태그라인
///   중단 — 이메일/비밀번호 폼 + 로그인 버튼 + 회원가입 링크
///   하단 — [_LoginButtons] 카카오/구글 소셜 버튼
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // 소셜 로그인 진행 상태(이메일 로그인 상태는 emailAuthControllerProvider에서 구독).
  bool _socialLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 소셜 로그인 액션을 실행한다.
  /// 성공 시 onAuthStateChange → 라우터 가드가 메인 화면으로 이동시킨다.
  Future<void> _runSocial(Future<void> Function() action) async {
    setState(() => _socialLoading = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, '로그인에 실패했어요', isError: true);
      }
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  /// 이메일 로그인 제출. 미인증 계정이면 확인 안내 화면으로 유도한다.
  Future<void> _submitEmailSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    try {
      await ref.read(emailAuthControllerProvider.notifier).submitSignIn(
            email: email,
            password: _passwordController.text,
          );
      // 성공 → 세션 발생 → 라우터 가드가 메인으로 이동시킨다.
    } on Failure catch (f) {
      if (!mounted) return;
      showAppSnackBar(context, f.message, isError: true);
      // 미인증이면 확인 메일 안내 화면으로 보내 재전송을 돕는다.
      if (f.code == 'EMAIL_NOT_CONFIRMED') {
        context.push('/signup/confirm', extra: email);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(authControllerProvider.notifier);
    final emailLoading = ref.watch(emailAuthControllerProvider).isLoading;
    final loading = _socialLoading || emailLoading;

    return Scaffold(
      // 베이스 단색 — tea_sel.mp4의 스튜디오 회색 배경(#EEF0F2)과 맞춰
      // 영상 사각 테두리가 완전히 묻히도록 처리
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 베이스 단색 (영상 배경과 동일한 옅은 회색) ──
          const ColoredBox(color: Color(0xFFEEF0F2)),
          // ── 실제 콘텐츠 레이어 ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.vertical,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.xxl),
                      const _BrandSection(),
                      const SizedBox(height: AppSpacing.xxl),
                      _EmailLoginForm(
                        formKey: _formKey,
                        emailController: _emailController,
                        passwordController: _passwordController,
                        loading: loading,
                        onSubmit: _submitEmailSignIn,
                        onSignUpTap: () => context.push('/signup'),
                        onForgotTap: () => context.push('/forgot-password'),
                      ),
                      const Spacer(),
                      const _OrDivider(),
                      const SizedBox(height: AppSpacing.lg),
                      _LoginButtons(
                        loading: loading,
                        onKakaoTap: () =>
                            _runSocial(controller.signInWithKakao),
                        onGoogleTap: () =>
                            _runSocial(controller.signInWithGoogle),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
              ),
            ),
          ),          // Padding 닫기
        ),            // SafeArea 닫기
        ],            // Stack.children 리스트 닫기
      ),              // Stack 닫기
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 브랜드 영역
// ─────────────────────────────────────────────────────────────

/// 마스코트 영상 + 그라데이션 워드마크 + 태그라인으로 구성된 브랜드 섹션.
///
/// 마스코트는 `box_sel.mp4`를 화면 진입 시 **한 번만**(무한 반복 X) 음소거 자동 재생한다.
/// 초기화 전·로드 실패 시에는 정지 이미지(`mascot.png`)를 같은 폭으로 보여
/// 검은 박스 깜빡임이나 레이아웃 점프를 막는다.
class _BrandSection extends StatefulWidget {
  const _BrandSection();

  @override
  State<_BrandSection> createState() => _BrandSectionState();
}

class _BrandSectionState extends State<_BrandSection> {
  // 히어로 영상 폭(기존 정지 이미지 180 → 히어로 260으로 확대).
  static const double _heroWidth = 260;

  late final VideoPlayerController _controller;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/videos/tea_sel.mp4')
      ..setVolume(0); // 음소거
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _videoReady = true);
      _controller.play(); // 화면 진입 시 한 번만 재생(setLooping 미호출)
    }).catchError((Object _) {
      // 초기화 실패 시 폴백 이미지를 계속 노출한다(_videoReady=false 유지).
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // 컨트롤러 누수 방지
    super.dispose();
  }

  /// 영상 초기화 전·실패 시 보여줄 정지 마스코트(+이미지 로드 실패 폴백 배지).
  Widget _fallbackMascot() => Image.asset(
        'assets/images/mascot.png',
        width: _heroWidth,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.card + 8),
          ),
          child: const Icon(Icons.edit_rounded, size: 44, color: AppColors.primary),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 마스코트 — box_sel.mp4 히어로 영상(초기화 전·실패 시 정지 이미지 폴백)
        _videoReady
            ? SizedBox(
                width: _heroWidth,
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : _fallbackMascot(),
        const SizedBox(height: AppSpacing.lg),
        // 그라데이션 워드마크 — WantedSans 800 48px, [바이올렛→블루→시안] 100deg
        ShaderMask(
          shaderCallback: (Rect bounds) => const LinearGradient(
            transform: GradientRotation(1.745), // 100deg in radians
            colors: [
              Color(0xFF7C3AED), // 바이올렛
              Color(0xFF3366FF), // 블루
              Color(0xFF06B6D4), // 시안
            ],
            stops: [0.0, 0.52, 1.0],
          ).createShader(bounds),
          child: const Text(
            'recorme',
            style: TextStyle(
              fontFamily: 'PoorStory',
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: Colors.white, // ShaderMask가 이 색을 그라데이션으로 대체한다
              letterSpacing: -1.0,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // 태그라인 — accent(바이올렛), WantedSans 700 15px
        const Text(
          '오늘 하루, 콕 찍어 기록해요',
          style: TextStyle(
            fontFamily: 'PoorStory',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 이메일 로그인 폼
// ─────────────────────────────────────────────────────────────

/// 이메일/비밀번호 입력 + 로그인 버튼 + 회원가입 링크.
class _EmailLoginForm extends StatelessWidget {
  const _EmailLoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.onSubmit,
    required this.onSignUpTap,
    required this.onForgotTap,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onSignUpTap;
  final VoidCallback onForgotTap;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: emailController,
            label: '이메일',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !loading,
            validator: AuthValidators.email,
          ),
          const SizedBox(height: AppSpacing.sm),
          AuthTextField(
            controller: passwordController,
            label: '비밀번호',
            obscureText: true,
            textInputAction: TextInputAction.done,
            enabled: !loading,
            validator: AuthValidators.password,
            onFieldSubmitted: (_) => loading ? null : onSubmit(),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15), // 시안 기준 15dp
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.surface,
                    ),
                  )
                : const Text('로그인'),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 회원가입 / 비밀번호 찾기 보조 액션
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: loading ? null : onSignUpTap,
                child: const Text('이메일로 회원가입'),
              ),
              TextButton(
                onPressed: loading ? null : onForgotTap,
                child: const Text('비밀번호를 잊으셨나요?'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "또는" 구분선.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.hairline, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            '또는',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkMuted),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.hairline, thickness: 1)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 소셜 로그인 버튼 영역
// ─────────────────────────────────────────────────────────────

/// 카카오/구글 버튼 컨테이너. [loading]이면 두 버튼을 비활성화한다.
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
        _KakaoButton(onTap: loading ? null : onKakaoTap),
        const SizedBox(height: AppSpacing.sm),
        _GoogleButton(onTap: loading ? null : onGoogleTap),
      ],
    );
  }
}

/// 카카오 브랜드 버튼.
///
/// 배경 #FEE500, 텍스트 #191600 — Kakao Design System 지정 고정값.
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
          borderRadius: BorderRadius.circular(15), // 시안 기준 15dp
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      // 아이콘은 좌측 정렬, 라벨은 가운데 정렬
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.chat_bubble, size: 20),
          ),
          Text('카카오 로그인'),
        ],
      ),
    );
  }
}

/// 구글 OutlinedButton. 흰 배경 + hairline 테두리 + 공식 멀티컬러 'G' 로고.
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
          borderRadius: BorderRadius.circular(15), // 시안 기준 15dp
        ),
        side: const BorderSide(color: AppColors.hairline, width: 1.5),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Opacity(
              opacity: onTap != null ? 1.0 : 0.4,
              child: SvgPicture.asset(
                'assets/icons/google_g.svg',
                width: 20,
                height: 20,
              ),
            ),
          ),
          const Text('Google 로그인'),
        ],
      ),
    );
  }
}
