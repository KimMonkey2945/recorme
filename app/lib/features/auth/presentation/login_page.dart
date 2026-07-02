import 'dart:math';

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

/// 마스코트 영상 1편의 표시 설정(경로·베이스 배경색·히어로 폭).
///
/// 영상마다 해상도와 스튜디오 배경 톤이 달라, 로그인 화면 베이스 색과 표시 폭을
/// 영상별로 묶어 관리한다. 베이스 색을 영상 배경과 맞춰 사각 테두리(seam)를 없앤다.
class _MascotVideo {
  const _MascotVideo(this.asset, this.bgColor, this.maxWidth,
      {this.feather = false});

  final String asset;
  final Color bgColor; // 로그인 베이스 색(= 영상 배경 톤). 가장자리 페이드 색으로도 사용
  final double maxWidth; // 표시 최대 폭. 가용 폭과 min → 모바일은 화면 가득, 데스크톱은 cap
  final bool feather; // 가장자리를 bgColor로 부드럽게 덮어 영상 사각 경계를 지운다(와이드 전용)

  /// 한 편을 무작위로 고른다(화면 진입 시 1회).
  static _MascotVideo pickRandom() => _all[Random().nextInt(_all.length)];

  static const List<_MascotVideo> _all = [
    // 정사각(640×640) — 배경이 페이지와 같은 밝은 회색이라 경계가 거의 없음
    _MascotVideo('assets/videos/tea_sel.mp4', Color(0xFFEEF0F2), 260),
    _MascotVideo('assets/videos/box_sel.mp4', Color(0xFFEEF0F2), 260),
    // 16:9 와이드(1280×720) — 배경이 페이지보다 진한 회색 그라데이션이고 프레임마다
    // 밝기가 달라 단색만으로는 경계가 남는다. 베이스 색을 가장자리 톤에 맞추고
    // 추가로 4변을 페이드(feather)해 사각 경계를 지운다. 폭도 크게(560까지) 키운다.
    _MascotVideo('assets/videos/ballet_sel.mp4', Color(0xFFCFD0D2), 560,
        feather: true),
  ];
}

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

  // 화면 진입 시 한 번만 추첨한 마스코트 영상(베이스 색·재생·표시 폭의 단일 출처).
  // build에서 뽑으면 로딩 상태 rebuild마다 재추첨되므로 initState에서 1회 고정한다.
  late final _MascotVideo _mascot;

  @override
  void initState() {
    super.initState();
    _mascot = _MascotVideo.pickRandom();
  }

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
      // 베이스 단색 — 뽑힌 마스코트 영상의 배경색(_mascot.bgColor)에 맞춰
      // 영상 사각 테두리가 완전히 묻히도록 처리(영상마다 배경 톤이 달라 색을 맞춘다)
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 베이스 단색 (뽑힌 영상 배경과 동일한 톤) ──
          ColoredBox(color: _mascot.bgColor),
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
                      _BrandSection(video: _mascot),
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
                        // 카카오 로그인 미사용 — 콜백 배선 주석(추후 사용 시 해제).
                        // onKakaoTap: () =>
                        //     _runSocial(controller.signInWithKakao),
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
/// 재생할 영상은 부모(`_LoginPageState`)가 진입 시 1회 추첨해 [video]로 전달한다
/// (베이스 배경색과 동일 출처). 화면 진입 시 **한 번만**(무한 반복 X) 음소거 자동 재생한다.
/// 초기화 전·로드 실패 시에는 정지 이미지(`mascot.png`)를 같은 폭으로 보여
/// 검은 박스 깜빡임이나 레이아웃 점프를 막는다.
class _BrandSection extends StatefulWidget {
  const _BrandSection({required this.video});

  /// 부모가 추첨해 전달한 마스코트 영상 설정(경로·배경색·표시 폭).
  final _MascotVideo video;

  @override
  State<_BrandSection> createState() => _BrandSectionState();
}

class _BrandSectionState extends State<_BrandSection> {
  late final VideoPlayerController _controller;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.video.asset)
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
  Widget _fallbackMascot(double width) => Image.asset(
        'assets/images/mascot.png',
        width: width,
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

  /// 히어로 영상. [feather]면 4변을 배경색으로 페이드해 사각 경계를 지운다.
  Widget _heroVideo(double width) {
    final player = AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: widget.video.feather
          ? Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(_controller),
                // 가장자리를 베이스 색으로 부드럽게 덮음 → 뒤 ColoredBox(같은 색)와 이어져
                // 영상 경계가 사라진다. 프레임별 배경 밝기 차이도 이 페이드가 흡수한다.
                IgnorePointer(child: _EdgeFade(color: widget.video.bgColor)),
              ],
            )
          : VideoPlayer(_controller),
    );
    return SizedBox(width: width, child: player);
  }

  @override
  Widget build(BuildContext context) {
    // 히어로 폭 = min(설정 maxWidth, 가용 폭) → 모바일은 화면 가득, 데스크톱은 cap.
    // 가용 폭 = 화면폭 - 좌우 콘텐츠 패딩(AppSpacing.xxl*2).
    // LayoutBuilder는 상위 IntrinsicHeight와 충돌하므로 MediaQuery로 계산한다.
    final available = MediaQuery.sizeOf(context).width - AppSpacing.xxl * 2;
    final w = widget.video.maxWidth < available
        ? widget.video.maxWidth
        : available;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 마스코트 — 랜덤 히어로 영상(초기화 전·실패 시 정지 이미지 폴백).
        _videoReady ? _heroVideo(w) : _fallbackMascot(w),
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

/// 영상 위에 얹어 4변을 [color]로 부드럽게 페이드시키는 오버레이.
///
/// 각 변에서 안쪽으로 사라지는 선형 그라데이션 4장을 겹친다. 뒤 베이스([color]와
/// 동일)와 이어져 영상의 사각 경계가 눈에 띄지 않게 녹아든다. 페이드 폭은 짧은 변
/// 대비 비율이라 어떤 크기에서도 균일하게 보인다.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.color});

  final Color color;

  // 페이드 폭(각 변 기준 비율). 피사체를 과하게 먹지 않도록 얇게 유지한다.
  static const double _fadeX = 0.10; // 좌·우
  static const double _fadeY = 0.16; // 상·하

  @override
  Widget build(BuildContext context) {
    final transparent = color.withAlpha(0);

    Widget grad(Alignment begin, Alignment end) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [color, transparent],
            ),
          ),
        );

    // 영상 크기를 받아 각 변 페이드 폭을 픽셀로 계산하고 Positioned로 배치한다
    // (Align/FractionallySizedBox 조합은 DecoratedBox에 무한 제약을 넘겨 레이아웃 실패).
    return LayoutBuilder(
      builder: (context, c) {
        final fx = c.maxWidth * _fadeX;
        final fy = c.maxHeight * _fadeY;
        return Stack(
          children: [
            // 상단: 위 → 아래로 사라짐
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: fy,
                child: grad(Alignment.topCenter, Alignment.bottomCenter)),
            // 하단: 아래 → 위로 사라짐
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: fy,
                child: grad(Alignment.bottomCenter, Alignment.topCenter)),
            // 좌측: 왼쪽 → 오른쪽으로 사라짐
            Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: fx,
                child: grad(Alignment.centerLeft, Alignment.centerRight)),
            // 우측: 오른쪽 → 왼쪽으로 사라짐
            Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: fx,
                child: grad(Alignment.centerRight, Alignment.centerLeft)),
          ],
        );
      },
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
    // 카카오 로그인 미사용 — 추후 사용 시 주석 해제.
    // required this.onKakaoTap,
    required this.onGoogleTap,
  });

  final bool loading;
  // final VoidCallback onKakaoTap;
  final VoidCallback onGoogleTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 카카오 로그인 미사용 — 버튼 숨김(추후 사용 시 아래 두 줄 주석 해제).
        // _KakaoButton(onTap: loading ? null : onKakaoTap),
        // const SizedBox(height: AppSpacing.sm),
        _GoogleButton(onTap: loading ? null : onGoogleTap),
      ],
    );
  }
}

// 카카오 로그인 미사용 — 버튼 위젯 전체 주석(추후 사용 시 아래 블록 주석 해제).
/*
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
*/

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
