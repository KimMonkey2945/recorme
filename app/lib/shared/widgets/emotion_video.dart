import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/emotion_assets.dart';
import 'emotion_avatar.dart';

/// 감정 코드에 대응하는 마스코트 영상을 **투명 배경(캐릭터만)**으로 표시하는 위젯.
///
/// ## 투명 처리 원리 (알파 매트 패킹 + 셰이더)
/// 어떤 영상 코덱도 iOS+Android 동시 네이티브 투명을 주지 못한다(H.264=알파 없음,
/// VP9-알파 webm=iOS 미재생·Android 알파 무시). 그래서 투명을 코덱이 아니라 앱에서 만든다:
/// - 에셋은 **불투명 H.264 mp4**([좌: 캐릭터 색 | 우: 실루엣 알파], 2:1)로 전 플랫폼 재생.
/// - `flutter_shaders`의 [AnimatedSampler]로 프레임을 [ui.FragmentShader]에 통과시켜
///   좌 절반(색)·우 절반(알파)을 합쳐 배경을 투명 처리 → 캐릭터만 렌더(iOS·Android).
/// - Android/Skia에서도 동작 검증됨(Impeller off 환경 포함).
///
/// ## 플랫폼
/// - **모바일(iOS/Android)**: 위 셰이더 합성 영상.
/// - **웹**: `video_player`가 DOM 오버레이라 셰이더 합성이 안 되므로, 정적 투명 PNG
///   포스터([EmotionAvatar])를 렌더한다(개발 테스트용, 배포 대상 아님).
///
/// ## 폴백
/// 영상/셰이더 준비 전·초기화 실패 시 [EmotionAvatar](PNG)를 같은 자리에 렌더해
/// 검은 박스·레이아웃 점프를 막는다(위젯 테스트·무플러그인 환경 포함).
///
/// ## 크기
/// - [size] 지정: [size]×[size] 정사각형 안에 캐릭터를 contain으로 맞춘다(전체 표시).
/// - [size] null: 부모 가로폭을 채우고 캐릭터 원본 비율로 높이를 정한다.
class EmotionVideo extends StatefulWidget {
  const EmotionVideo({
    super.key,
    required this.emotionCode,
    this.size,
    this.moodEmoji,
    this.cornerRadius = 0.0,
    this.semanticLabel,
  });

  /// 감정 코드 (예: 'JOY'). null·미상이면 neutral 영상.
  final String? emotionCode;

  /// 고정 크기(dp). null이면 부모 폭 채움 모드.
  final double? size;

  /// 영상·이미지 모두 실패 시 텍스트 폴백 이모지.
  final String? moodEmoji;

  /// ClipRRect 모서리 반경. 0이면 클리핑 없음.
  final double cornerRadius;

  /// 접근성 라벨. null이면 [emotionCode] 기반 자동 라벨, ''이면 시맨틱 생략.
  final String? semanticLabel;

  @override
  State<EmotionVideo> createState() => _EmotionVideoState();
}

class _EmotionVideoState extends State<EmotionVideo>
    with SingleTickerProviderStateMixin {
  /// 알파 합성 셰이더 프로그램(전 인스턴스 공유 — 로드는 1회).
  static Future<ui.FragmentProgram>? _programFuture;

  VideoPlayerController? _controller;
  ui.FragmentShader? _shader;
  bool _videoReady = false;

  /// 매 프레임 리페인트 구동용 티커.
  /// AnimatedSampler는 리페인트 시에만 영상 프레임을 재샘플링하므로, 영상이 계속
  /// 움직이려면(외부 텍스처는 프레임 갱신이 리페인트를 유발하지 않음) 이 티커로
  /// 매 프레임 강제 리페인트해야 한다(없으면 첫 프레임에서 멈춰 보인다).
  AnimationController? _repaint;

  /// 비동기 초기화 도중 컨트롤러가 교체될 때 구 콜백을 무시하기 위한 버전.
  int _initVersion = 0;

  @override
  void initState() {
    super.initState();
    // 웹은 셰이더 합성이 불가하므로 영상을 초기화하지 않고 PNG 포스터만 렌더한다.
    if (!kIsWeb) {
      _repaint = AnimationController(vsync: this, duration: const Duration(seconds: 1));
      _loadShader();
      _initController(widget.emotionCode);
    }
  }

  @override
  void didUpdateWidget(covariant EmotionVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 감정 코드가 바뀌면(PENDING→DONE 등) 컨트롤러를 교체한다(웹은 영상 미사용).
    if (!kIsWeb && oldWidget.emotionCode != widget.emotionCode) {
      final stale = _controller; // 기존 컨트롤러 캡처
      setState(() => _videoReady = false);
      _initController(widget.emotionCode); // _controller를 새 것으로 교체
      stale?.dispose(); // 기존 것 해제
    }
  }

  /// 알파 합성 셰이더를 로드한다(프로그램은 공유 캐시, 인스턴스별 shader 생성).
  Future<void> _loadShader() async {
    try {
      final program =
          await (_programFuture ??= ui.FragmentProgram.fromAsset('shaders/emotion_alpha.frag'));
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // 셰이더 로드 실패 시 PNG 폴백 유지.
    }
  }

  /// 에셋 경로로 컨트롤러를 생성하고 자동재생·무한루프·무음을 설정한다.
  void _initController(String? code) {
    final version = ++_initVersion; // 이 호출의 버전 스냅숏
    final controller = VideoPlayerController.asset(EmotionAssets.videoOf(code))
      ..setVolume(0); // 무음 — 웹 autoplay 정책 충족
    _controller = controller;
    controller.initialize().then((_) {
      // mounted + 버전 검사로 폐기된 콜백 무시
      if (!mounted || version != _initVersion) return;
      controller.setLooping(true); // 무한 루프
      controller.play();
      // 매 프레임 리페인트 시작(셰이더 재샘플링 → 영상이 실제로 움직인다).
      if (!(_repaint?.isAnimating ?? true)) _repaint?.repeat();
      setState(() => _videoReady = true);
    }).catchError((Object _) {
      // 초기화 실패 시 _videoReady=false 유지 → PNG 폴백 계속 노출
    });
  }

  @override
  void dispose() {
    _repaint?.dispose();
    _controller?.dispose(); // 컨트롤러 누수 방지
    _shader?.dispose();
    super.dispose();
  }

  /// 패킹 영상을 셰이더로 합성해 캐릭터만(투명 배경) 렌더한다.
  /// [explicitSize] 지정 시 캐릭터 원본 크기로 그린 뒤 바깥에서 contain 스케일한다.
  Widget _composited(VideoPlayerController controller, ui.FragmentShader shader) {
    // 패킹 프레임은 2W×H. 캐릭터 종횡비 = (packedW/2)/packedH.
    final packed = controller.value.size;
    final charAspect = (packed.width / 2) / packed.height;

    // 자식(VideoPlayer)이 캐릭터 종횡비 박스를 채우며 패킹 2:1을 압축 → 셰이더가 복원.
    final Widget video = VideoPlayer(controller);
    return AspectRatio(
      aspectRatio: charAspect,
      // 티커로 매 프레임 리빌드 → AnimatedSampler가 새 영상 프레임을 재샘플링(부드러운 재생).
      child: AnimatedBuilder(
        animation: _repaint ?? kAlwaysCompleteAnimation,
        builder: (context, child) => AnimatedSampler(
          (ui.Image image, Size size, Canvas canvas) {
            shader
              ..setFloat(0, size.width) // uSize.x
              ..setFloat(1, size.height) // uSize.y
              ..setImageSampler(0, image); // uTex
            canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
          },
          child: child!,
        ),
        child: video,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String resolved =
        widget.semanticLabel ?? EmotionAssets.labelOf(widget.emotionCode);
    final double? size = widget.size;

    final controller = _controller;
    final shader = _shader;
    final bool ready = !kIsWeb &&
        _videoReady &&
        controller != null &&
        shader != null &&
        controller.value.isInitialized;

    Widget result;
    if (size != null) {
      // ── 고정 정사각형 모드: 캐릭터를 contain으로 전체 표시 ──
      final Widget inner = ready
          // AspectRatio unbounded 회피: 캐릭터 원본 크기 SizedBox를 FittedBox로 정사각형에 맞춘다.
          ? FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: controller.value.size.width / 2, // 패킹 좌 절반(캐릭터) 폭
                height: controller.value.size.height,
                child: _composited(controller, shader),
              ),
            )
          // 영상 준비 전·실패·웹 — PNG 포스터(칩 배경 없이 이미지만)
          : EmotionAvatar(
              emotionCode: widget.emotionCode,
              size: size,
              moodEmoji: widget.moodEmoji,
              backgroundColor: Colors.transparent,
              semanticLabel: '', // 바깥 Semantics가 라벨 제공
            );
      result = SizedBox(
        width: size,
        height: size,
        child: widget.cornerRadius > 0
            ? ClipRRect(
                borderRadius: BorderRadius.circular(widget.cornerRadius),
                child: inner,
              )
            : inner,
      );
    } else {
      // ── 부모 폭 채움 모드: 캐릭터 원본 비율로 높이 결정 ──
      final Widget inner = ready
          ? _composited(controller, shader)
          : EmotionAvatar(
              emotionCode: widget.emotionCode,
              size: 120.0,
              moodEmoji: widget.moodEmoji,
              backgroundColor: Colors.transparent,
              semanticLabel: '',
            );
      result = widget.cornerRadius > 0
          ? ClipRRect(
              borderRadius: BorderRadius.circular(widget.cornerRadius),
              child: inner,
            )
          : inner;
    }

    return Semantics(
      label: resolved.isEmpty ? null : resolved,
      image: true,
      child: result,
    );
  }
}
