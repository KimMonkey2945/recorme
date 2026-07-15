import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 정적 PNG 한 장을 "살아 있는" 캐릭터로 보이게 하는 절차적 idle 애니메이션.
///
/// ## 왜 메시 변형인가
/// 이미지를 통째로 `Transform.rotate`/`scale` 하면 **딱딱한 판자가 흔들리는** 모양이 된다.
/// Rive가 자연스러운 이유는 런타임이 아니라 아트보드가 **메시로 리깅**돼 있기 때문이다.
/// 그래서 같은 원리를 Flutter에서 직접 구현한다 — PNG를 격자 메시로 쪼개고
/// [Canvas.drawVertices] + [ImageShader]로 **정점마다 다르게** 변형한다.
/// 발은 바닥에 붙어 있고, 위로 갈수록 크게 흔들리며, 숨쉴 때 몸이 눌렸다 늘어난다.
///
/// ## 착용 아이템 오버레이 ([overlayAssetPaths])
/// 아이템 PNG는 **캐릭터와 동일한 프레임**(같은 캔버스 비율, 아이템 외 영역 투명)으로
/// 제작한다는 전제다. 그러면 같은 정점 배열에 아이템 텍스처만 바꿔 [Canvas.drawVertices]를
/// 반복하는 것으로 아이템이 캐릭터와 **함께 숨쉬고 흔들린다**(앵커 계산이 필요 없다).
/// 목록 순서 = 그리는 순서(z 오름차순으로 정렬해 넘길 것). 로드 실패한 레이어는 조용히
/// 건너뛴다 — 아이템이 캐릭터 렌더 자체를 막아서는 안 된다.
///
/// ## 합성하는 움직임 (전부 정규화 높이 v = 발 0 → 머리 1 에 따라 가중된다)
/// - **스웨이**: 상체일수록 크게 좌우로 흔들린다(`v^1.6` 가중 → 발은 고정).
/// - **숨쉬기**: 바닥 기준 세로 스쿼시&스트레치. 부피 보존 근사로 가로는 반대로 움직인다.
/// - **두리번**: 주기 안 짧은 구간에서 **머리 쪽에만** 가로 변위를 줘 좌→우로 한 번 훑는다.
/// - **하모닉 합성**: 사인 하나면 메트로놈처럼 보인다. 기본 주기의 **정수배 하모닉**을
///   섞어 유기적으로 만들되, 정수배라 루프 경계에서 끊기지 않는다.
///
/// [phase](0~1)를 캐릭터마다 다르게 주면 여러 캐릭터가 같은 박자로 움직이지 않는다.
///
/// ## 테스트에서의 hang 방지 (중요)
/// 무한 반복 애니메이션은 `pumpAndSettle()`을 영원히 끝나지 않게 만든다. 두 가지 차단책:
/// 1. [animate]`= false`: 정지 상태로 그린다(캐러셀의 옆 카드도 이걸 쓴다).
/// 2. [debugDisableIdleAnimation]`= true`: 라우터가 페이지를 직접 만들어 [animate]를
///    주입할 수 없는 테스트(리다이렉트 테스트 등)를 위한 전역 스위치.
class IdleCharacterView extends StatefulWidget {
  const IdleCharacterView({
    super.key,
    required this.assetPath,
    this.overlayAssetPaths = const [],
    this.animate = true,
    this.phase = 0,
  });

  /// 캐릭터 이미지 에셋 경로('assets/characters/monkey.png').
  /// 서버가 내려주는 thumbnailUrl이 곧 이 경로다(URL 아님).
  final String assetPath;

  /// 착용 아이템 레이어 경로 목록(z 오름차순 = 그리는 순서).
  /// 캐릭터와 동일 프레임의 투명 PNG여야 같은 메시에 정확히 얹힌다.
  final List<String> overlayAssetPaths;

  /// idle 애니메이션 재생 여부. false면 정지(캐러셀 비중앙 카드·테스트).
  final bool animate;

  /// 위상 오프셋(0~1). 캐릭터마다 달리 줘 동작이 겹치지 않게 한다.
  final double phase;

  /// 테스트 전역 스위치: true면 [animate]와 무관하게 애니메이션을 끈다.
  @visibleForTesting
  static bool debugDisableIdleAnimation = false;

  @override
  State<IdleCharacterView> createState() => _IdleCharacterViewState();
}

class _IdleCharacterViewState extends State<IdleCharacterView> {
  /// 메시 셰이더의 소스가 되는 raw 이미지.
  /// 로드 전/실패면 null이고, 그동안은 [Image.asset] 폴백으로 그린다
  /// (이미지 디코딩이 없는 위젯 테스트 환경도 이 경로로 안전하게 통과한다).
  ui.Image? _image;

  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// 오버레이 레이어. 경로별로 해석 상태를 따로 들고, 실패(null)는 그릴 때 건너뛴다.
  final Map<String, ui.Image?> _overlayImages = {};
  final Map<String, ImageStream> _overlayStreams = {};
  final Map<String, ImageStreamListener> _overlayListeners = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
    _resolveOverlays();
  }

  @override
  void didUpdateWidget(covariant IdleCharacterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _image = null;
      _resolveImage();
    }
    if (!listEquals(oldWidget.overlayAssetPaths, widget.overlayAssetPaths)) {
      _resolveOverlays();
    }
  }

  /// 에셋을 raw [ui.Image]로 해석한다. 실패하면 폴백 렌더로 남는다.
  void _resolveImage() {
    final provider = AssetImage(widget.assetPath);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;

    _detachStream();
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) {
          info.image.dispose();
          return;
        }
        setState(() => _image = info.image);
      },
      // 로드 실패는 치명적이지 않다 — 폴백(Image.asset의 errorBuilder)이 받는다.
      onError: (_, _) {
        if (mounted) setState(() => _image = null);
      },
    );
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  /// 오버레이 경로 목록을 현재 위젯 상태에 맞춘다.
  /// 빠진 경로는 구독 해제, 새 경로는 해석 시작. 실패한 레이어는 null로 남아 스킵된다.
  void _resolveOverlays() {
    final wanted = widget.overlayAssetPaths.toSet();

    for (final path in _overlayStreams.keys.toList()) {
      if (!wanted.contains(path)) _detachOverlay(path);
    }

    for (final path in wanted) {
      if (_overlayStreams.containsKey(path)) continue;
      final stream =
          AssetImage(path).resolve(createLocalImageConfiguration(context));
      final listener = ImageStreamListener(
        (info, _) {
          if (!mounted) {
            info.image.dispose();
            return;
          }
          setState(() => _overlayImages[path] = info.image);
        },
        // 아이템 로드 실패는 캐릭터 렌더를 막지 않는다 — 해당 레이어만 빠진다.
        onError: (_, _) {
          if (mounted) setState(() => _overlayImages[path] = null);
        },
      );
      _overlayStreams[path] = stream..addListener(listener);
      _overlayListeners[path] = listener;
    }
  }

  void _detachStream() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _detachOverlay(String path) {
    final stream = _overlayStreams.remove(path);
    final listener = _overlayListeners.remove(path);
    if (stream != null && listener != null) stream.removeListener(listener);
    _overlayImages.remove(path);
  }

  @override
  void dispose() {
    _detachStream();
    for (final path in _overlayStreams.keys.toList()) {
      _detachOverlay(path);
    }
    super.dispose();
  }

  /// 현재 로드된 오버레이를 위젯의 경로 순서(z 오름차순)대로 돌려준다.
  List<ui.Image> _loadedOverlays() => [
        for (final path in widget.overlayAssetPaths)
          if (_overlayImages[path] != null) _overlayImages[path]!,
      ];

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return _fallback();

    final shouldAnimate =
        widget.animate && !IdleCharacterView.debugDisableIdleAnimation;

    // 정지 상태(옆 카드·테스트)에서는 Ticker를 아예 만들지 않는다.
    if (!shouldAnimate) {
      return CustomPaint(
        painter: _MeshCharacterPainter(
          image: image,
          overlays: _loadedOverlays(),
          t: 0,
        ),
        size: Size.infinite,
      );
    }

    return _AnimatedMesh(
      image: image,
      overlays: _loadedOverlays(),
      phase: widget.phase,
    );
  }

  /// 이미지가 아직 없을 때(로딩/실패/테스트)의 폴백.
  Widget _fallback() => Image.asset(
    widget.assetPath,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) =>
        const Center(child: Icon(Icons.pets_rounded, size: 48)),
  );
}

/// 메시를 매 프레임 다시 그리는 애니메이션 래퍼.
///
/// 컨트롤러를 [IdleCharacterView]가 아니라 여기서 들고 있는 이유:
/// 정지 상태에서는 이 위젯 자체가 트리에 없으므로 **Ticker가 생성조차 되지 않는다**.
class _AnimatedMesh extends StatefulWidget {
  const _AnimatedMesh({
    required this.image,
    required this.overlays,
    required this.phase,
  });

  final ui.Image image;
  final List<ui.Image> overlays;
  final double phase;

  @override
  State<_AnimatedMesh> createState() => _AnimatedMeshState();
}

class _AnimatedMeshState extends State<_AnimatedMesh>
    with SingleTickerProviderStateMixin {
  /// 마스터 컨트롤러. 모든 움직임을 이 값(0~1)에서 파생한다.
  ///
  /// 주기를 길게(12초) 잡고 그 안에 정수배 하모닉을 섞어야 반복이 눈에 덜 띈다.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = (_controller.value + widget.phase) % 1.0;
        return CustomPaint(
          painter: _MeshCharacterPainter(
            image: widget.image,
            overlays: widget.overlays,
            t: t,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// PNG를 격자 메시로 변형해 그리는 페인터.
///
/// 정점 좌표만 매 프레임 다시 계산하고, UV(텍스처 좌표)와 인덱스는 불변이다.
/// [overlays]는 캐릭터와 같은 정점 배열을 공유해 **같은 워프 필드**로 그려진다 —
/// 아이템이 캐릭터에 붙어 함께 움직이는 이유가 이것이다.
class _MeshCharacterPainter extends CustomPainter {
  _MeshCharacterPainter({
    required this.image,
    this.overlays = const [],
    required this.t,
  });

  final ui.Image image;

  /// 착용 아이템 레이어(z 오름차순). 캐릭터와 동일 프레임 전제.
  final List<ui.Image> overlays;

  /// 정규화 시간(0~1). 12초 주기 안의 위치.
  final double t;

  /// 격자 해상도. 세로를 촘촘히 둬야 상하 변형 기울기가 매끄럽다.
  static const int _cols = 12;
  static const int _rows = 16;

  // ── 변형 강도(모두 dest rect 크기 대비 비율) ──
  /// 좌우 스웨이 최대 진폭(폭 대비).
  static const double _swayAmount = 0.030;

  /// 숨쉬기 세로 신축률.
  static const double _breathAmount = 0.022;

  /// 두리번(머리 훑기) 최대 진폭(폭 대비).
  static const double _glanceAmount = 0.026;

  /// 두리번이 일어나는 구간(주기의 앞 20%).
  static const double _glanceWindow = 0.20;

  @override
  void paint(Canvas canvas, Size size) {
    // BoxFit.contain — 카드 안에서 비율을 유지한다.
    final imageW = image.width.toDouble();
    final imageH = image.height.toDouble();
    final scale = math.min(size.width / imageW, size.height / imageH);
    final destW = imageW * scale;
    final destH = imageH * scale;
    final left = (size.width - destW) / 2;
    final top = (size.height - destH) / 2;
    final bottom = top + destH;
    final centerX = left + destW / 2;

    final tau = 2 * math.pi * t;

    // 스웨이: 2·3 하모닉을 섞어 단조로운 좌우 왕복을 피한다.
    final sway =
        (math.sin(2 * tau) * 0.7 + math.sin(3 * tau + 1.1) * 0.3) *
        _swayAmount *
        destW;

    // 숨쉬기: 5 하모닉(주기당 5회 ≈ 2.4초에 한 번) + 7 하모닉으로 미세한 불규칙.
    final breath =
        (math.sin(5 * tau) * 0.85 + math.sin(7 * tau + 0.6) * 0.15) *
        _breathAmount;
    final scaleY = 1.0 + breath;
    // 부피 보존 근사 — 세로로 늘면 가로는 줄어든다(스쿼시&스트레치).
    final scaleX = 1.0 / math.sqrt(scaleY);

    // 두리번: 주기 앞 구간에서 사인 한 주기를 태워 좌→우로 훑고 0으로 복귀한다.
    // sin(0)=sin(2π)=0이라 구간 경계에서 값이 튀지 않는다.
    final glance = t < _glanceWindow
        ? math.sin(2 * math.pi * (t / _glanceWindow)) * _glanceAmount * destW
        : 0.0;

    final vertexCount = (_cols + 1) * (_rows + 1);
    final positions = Float32List(vertexCount * 2);

    var i = 0;
    for (var row = 0; row <= _rows; row++) {
      // v: 발 0 → 머리 1 (row 0이 이미지 위쪽 = 머리이므로 뒤집는다)
      final rowRatio = row / _rows;
      final v = 1.0 - rowRatio;

      // 발이 바닥에 붙어 있도록 위로 갈수록 변위를 키운다.
      final swayWeight = math.pow(v, 1.6).toDouble();
      // 두리번은 상체·머리에만(0.55 아래는 거의 0).
      final headWeight = _smoothstep(0.55, 1.0, v);

      for (var col = 0; col <= _cols; col++) {
        final colRatio = col / _cols;

        final baseX = left + destW * colRatio;
        final baseY = top + destH * rowRatio;

        // 숨쉬기: 바닥(bottom)을 기준으로 세로 신축, 중심선 기준 가로 신축.
        var x = centerX + (baseX - centerX) * scaleX;
        var y = bottom - (bottom - baseY) * scaleY;

        // 스웨이 + 두리번: 높이에 따라 가중된 가로 변위.
        x += sway * swayWeight + glance * headWeight;

        positions[i] = x;
        positions[i + 1] = y;
        i += 2;
      }
    }

    // 캐릭터 → 아이템 순서(z 오름차순)로 같은 정점 배열에 텍스처만 바꿔 그린다.
    _drawLayer(canvas, positions, image);
    for (final overlay in overlays) {
      _drawLayer(canvas, positions, overlay);
    }
  }

  /// 한 레이어를 공유 정점 배열로 그린다. UV는 레이어 자신의 픽셀 크기로 만든다 —
  /// 해상도가 캐릭터와 달라도 프레임 비율만 같으면 정확히 겹친다.
  void _drawLayer(Canvas canvas, Float32List positions, ui.Image layer) {
    final layerW = layer.width.toDouble();
    final layerH = layer.height.toDouble();

    final vertexCount = (_cols + 1) * (_rows + 1);
    final texCoords = Float32List(vertexCount * 2);
    var i = 0;
    for (var row = 0; row <= _rows; row++) {
      final rowRatio = row / _rows;
      for (var col = 0; col <= _cols; col++) {
        final colRatio = col / _cols;
        // UV는 이미지 픽셀 좌표계(ImageShader가 identity 행렬이므로 그대로 매핑된다).
        texCoords[i] = layerW * colRatio;
        texCoords[i + 1] = layerH * rowRatio;
        i += 2;
      }
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: _indicesFor(_cols, _rows),
    );

    final paint = Paint()
      ..shader = ImageShader(
        layer,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      );

    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
  }

  @override
  bool shouldRepaint(covariant _MeshCharacterPainter old) =>
      old.t != t || old.image != image || !listEquals(old.overlays, overlays);
}

/// 격자 삼각형 인덱스. 격자 크기가 고정이라 한 번만 만들어 재사용한다.
Uint16List? _cachedIndices;
int? _cachedCols;
int? _cachedRows;

Uint16List _indicesFor(int cols, int rows) {
  if (_cachedIndices != null && _cachedCols == cols && _cachedRows == rows) {
    return _cachedIndices!;
  }

  final indices = Uint16List(cols * rows * 6);
  var i = 0;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      final topLeft = row * (cols + 1) + col;
      final topRight = topLeft + 1;
      final bottomLeft = topLeft + (cols + 1);
      final bottomRight = bottomLeft + 1;

      indices[i++] = topLeft;
      indices[i++] = bottomLeft;
      indices[i++] = topRight;

      indices[i++] = topRight;
      indices[i++] = bottomLeft;
      indices[i++] = bottomRight;
    }
  }

  _cachedIndices = indices;
  _cachedCols = cols;
  _cachedRows = rows;
  return indices;
}

/// GLSL의 smoothstep — [edge0] 아래는 0, [edge1] 위는 1, 사이는 부드럽게 보간.
double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
