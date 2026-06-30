import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/emotion_assets.dart';
import 'emotion_avatar.dart';

/// 감정 코드에 대응하는 마스코트 mp4를 자동재생·무한루프·무음으로 표시하는 위젯.
///
/// ## 패턴
/// `login_page.dart`의 `_BrandSection`이 정립한 영상 재생 흐름을 그대로 따른다.
/// (VideoPlayerController.asset → setVolume(0) → initialize → play → dispose)
/// 차이점은 두 가지:
/// - **무한 루프**(`setLooping(true)`) — 로그인은 1회 재생, 여기는 계속 움직여야 함.
/// - **감정 코드 변경 대응**(`didUpdateWidget`) — PENDING→DONE 전환 등으로
///   [emotionCode]가 바뀌면 컨트롤러를 교체한다. 비동기 초기화 도중 교체될 때
///   [_initVersion] 카운터로 stale 콜백을 무시해 누수를 막는다.
///
/// ## 폴백
/// 영상 준비 전·초기화 실패 시 [EmotionAvatar](PNG)를 같은 자리에 렌더해
/// 검은 박스·레이아웃 점프를 막는다. 위젯 테스트 환경(video_player 플랫폼 채널 없음)
/// 에서도 초기화가 실패해 자동으로 PNG 폴백이 렌더된다.
///
/// ## 크기
/// - [size] 지정: [size]×[size] 정사각형 안에 영상을 contain으로 맞춘다(전체 표시).
/// - [size] null: 부모 가로폭을 채우고 영상 원본 비율로 높이를 정한다.
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

class _EmotionVideoState extends State<EmotionVideo> {
  late VideoPlayerController _controller;
  bool _videoReady = false;

  /// 비동기 초기화 도중 컨트롤러가 교체될 때 구 콜백을 무시하기 위한 버전.
  int _initVersion = 0;

  @override
  void initState() {
    super.initState();
    _initController(widget.emotionCode);
  }

  @override
  void didUpdateWidget(covariant EmotionVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 감정 코드가 바뀌면(PENDING→DONE 등) 컨트롤러를 교체한다.
    if (oldWidget.emotionCode != widget.emotionCode) {
      final stale = _controller; // 기존 컨트롤러 캡처
      setState(() => _videoReady = false);
      _initController(widget.emotionCode); // _controller를 새 것으로 교체
      stale.dispose(); // 기존 것 해제
    }
  }

  /// 에셋 경로로 컨트롤러를 생성하고 자동재생·무한루프·무음을 설정한다.
  void _initController(String? code) {
    final version = ++_initVersion; // 이 호출의 버전 스냅숏
    _controller = VideoPlayerController.asset(EmotionAssets.videoOf(code))
      ..setVolume(0); // 무음 — 웹 autoplay 정책 충족
    _controller.initialize().then((_) {
      // mounted + 버전 검사로 폐기된 콜백 무시
      if (!mounted || version != _initVersion) return;
      _controller.setLooping(true); // 무한 루프
      _controller.play();
      setState(() => _videoReady = true);
    }).catchError((Object _) {
      // 초기화 실패 시 _videoReady=false 유지 → PNG 폴백 계속 노출
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // 컨트롤러 누수 방지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String resolved =
        widget.semanticLabel ?? EmotionAssets.labelOf(widget.emotionCode);
    final double? size = widget.size;

    Widget result;
    if (size != null) {
      // ── 고정 정사각형 모드: 영상을 contain으로 전체 표시 ──
      final Widget inner = _videoReady
          // 마스코트 전체(몸·손발)가 잘리지 않도록 contain. 명시적 크기 SizedBox로
          // AspectRatio unbounded 문제 회피하고, 정사각형 안에 레터박스로 맞춘다.
          ? FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            )
          // 영상 준비 전·실패 — PNG 포스터(칩 배경 없이 이미지만)
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
      // ── 부모 폭 채움 모드: 영상 원본 비율로 높이 결정 (login_page.dart 패턴) ──
      final Widget inner = _videoReady
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
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
