import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/emotion_video.dart';
import '../../domain/diary_content.dart';
import 'diary_image_embed_builder.dart';
import 'diary_quill_styles.dart';

/// 분석 진행 중 보조 문구(상수로 분리해 향후 일괄 수정 용이).
const String kAnalysisEtaText = '곧 이 날의 감정이 기록에 담길 거예요';

/// 전체화면 로딩 영상 에셋(감정 분석 PENDING 진입 시 1회 재생).
const String kRunningIntroAsset = 'assets/videos/running_sel.mp4';

/// 기록 상세 표현 위젯.
///
/// ## 배경 전략
/// 감정 배경색([backgroundColor])은 이 위젯이 아닌 **호출 측 Container**에서
/// AnimatedContainer로 적용한다. 이 위젯은 내부 콘텐츠(헤더·본문·버튼)만 담당.
///
/// ## 상태별 UI
/// | analysisStatus | 배지 | 헤더 추가 | 분석중 카드 |
/// |---|---|---|---|
/// | DRAFT   | '임시 저장' 배지 | 없음 | 없음 |
/// | PENDING | 없음 | 없음 | 표시 |
/// | DONE    | 없음 | 이모지·코멘트·제목 | 없음 |
/// | FAILED  | '분석 실패' 배지 | 없음 | 없음 |
///
/// [onEdit]이 null이면 수정 버튼을 숨긴다 — 확정 기록(analysisStatus != 'DRAFT')에서
/// 호출 측이 null로 전달한다.
class DiaryDetailView extends StatefulWidget {
  const DiaryDetailView({
    super.key,
    required this.dateText,
    required this.content,
    required this.analysisStatus,
    required this.onDelete,
    this.onEdit,
    this.pollingTimedOut = false,
    // 감정 테마 필드 (DONE 시에만 비-null)
    this.primaryEmotion,
    this.moodCardColor,
    this.textColor,
    this.accentColor,
    this.moodEmoji,
    this.aiComment,
    this.aiTitle,
  });

  /// 표시할 날짜 문자열 (예: '2026년 6월 24일 (화)').
  final String dateText;

  /// 본문(Quill Delta JSON 문자열. 레거시 plain text도 tolerant 처리).
  final String content;

  /// LLM 분석 상태 — 'DRAFT' / 'PENDING' / 'DONE' / 'FAILED'.
  final String analysisStatus;

  /// 수정 버튼 탭 콜백. null이면 수정 버튼을 숨긴다(확정 기록).
  final VoidCallback? onEdit;

  /// 삭제 버튼 탭 콜백 — 확인 다이얼로그는 호출 페이지가 처리.
  final VoidCallback onDelete;

  /// 폴링 타임아웃 여부. true이면 "잠시 후 다시 확인해 주세요" 안내로 전환.
  final bool pollingTimedOut;

  /// 감정 코드 (예: 'JOY'). 무드 카드의 마스코트 이미지 선택에 사용. DONE 시에만 비-null.
  final String? primaryEmotion;

  /// 무드 카드 채움색 — 감정 배경색(파스텔). DONE 시에만 비-null. 페이지 배경엔 쓰지 않음.
  final Color? moodCardColor;

  /// 감정 기반 텍스트 색(없으면 기본 잉크 색 사용).
  final Color? textColor;

  /// 감정 기반 강조색(이모지 칩·코멘트 색조 등에 활용).
  final Color? accentColor;

  /// AI 분석 무드 이모지 (예: "😊"). DONE 시 날짜 헤더에 표시.
  final String? moodEmoji;

  /// AI 생성 한 줄 코멘트. DONE 시 날짜 헤더 우측에 표시.
  final String? aiComment;

  /// AI 생성 제목. DONE 시 날짜 아래 보조 라인에 표시.
  final String? aiTitle;

  @override
  State<DiaryDetailView> createState() => _DiaryDetailViewState();
}

/// 감정 인트로 모션의 3단계.
/// - [big]: 이모지가 화면 중앙에 크게 차올라 감정 모션 표출(글을 가림).
/// - [settle]: 이모지가 글 하단 좌측 슬롯으로 작아지며 이동, 코멘트 페이드인.
/// - [rest]: 이모지(좌) + 코멘트(우)가 글 하단에 안착한 최종 상태.
enum _IntroPhase { big, settle, rest }

class _DiaryDetailViewState extends State<DiaryDetailView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late QuillController _controller;

  // ── 시네마틱 인트로 상태 ──────────────────────────────────────
  late final AnimationController _settleController;
  late final Animation<double> _curved;

  /// BIG 단계 머무는 시간을 재는 타이머(끝나면 SETTLE 시작).
  Timer? _dwellTimer;
  _IntroPhase _phase = _IntroPhase.big;

  /// 단일 영상 위젯 — 오버레이↔안착 슬롯 간 reparent해도 같은 컨트롤러를 유지(재시작 방지).
  final GlobalKey _videoKey = GlobalKey();

  /// 안착 슬롯 rect 측정용 키.
  final GlobalKey _slotKey = GlobalKey();

  /// 좌표 기준(Stack)으로 쓰는 키 — 슬롯 글로벌 좌표를 Stack 로컬로 변환.
  final GlobalKey _stackKey = GlobalKey();

  /// 측정된 안착 슬롯 rect(Stack 로컬 좌표). 측정 전엔 null.
  Rect? _restRect;

  /// 측정된 Stack 크기 — BIG 중앙 배치 계산용.
  Size? _stackSize;

  // ── 러닝 로딩 영상 상태 ───────────────────────────────────────

  /// 러닝 로딩 영상을 이번 방문에서 이미 트리거했는지(폴링 리빌드 재시작 방지, 방문당 1회).
  bool _runningIntroPlayed = false;

  /// 러닝 오버레이 마운트 여부.
  bool _runningVisible = false;

  /// 러닝 재생중+페이드 진행중(DONE 인트로 조기시작 차단용).
  bool _runningActive = false;

  /// 러닝 오버레이 불투명도(완료 시 1→0 페이드아웃).
  double _runningOpacity = 1;

  /// 러닝 페이드아웃 길이.
  static const Duration _kRunningFade = Duration(milliseconds: 500);

  // ── 인트로 튜닝 상수 ──────────────────────────────────────────
  /// BIG 단계 머무는 시간(감정 모션 표출).
  static const Duration _kDwell = Duration(milliseconds: 1800);

  /// SETTLE 단계 길이(작아지며 안착).
  static const Duration _kSettle = Duration(milliseconds: 700);

  /// BIG 단계 이모지 최대 크기(화면 폭의 90% 또는 이 값 중 작은 쪽).
  static const double _kBigMax = 320;

  /// 안착(REST) 이모지 크기.
  static const double _kRestSize = 72;

  /// DONE이고 감정 코드가 있어 인트로/안착을 보여줄 상태인지.
  bool _hasEmotion(DiaryDetailView w) =>
      w.analysisStatus == 'DONE' && w.primaryEmotion != null;

  @override
  void initState() {
    super.initState();
    _controller = _buildReadOnlyController(widget.content);
    _settleController = AnimationController(vsync: this, duration: _kSettle);
    _curved = CurvedAnimation(parent: _settleController, curve: Curves.easeInOutCubic);
    WidgetsBinding.instance.addObserver(this);
    // 첫 레이아웃 후 인트로 및 러닝 영상 시작(슬롯 측정·MediaQuery 접근 가능 시점).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startIntro();
      _maybeStartRunningIntro();
    });
  }

  @override
  void didUpdateWidget(covariant DiaryDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _controller.dispose();
      _controller = _buildReadOnlyController(widget.content);
    }
    // PENDING→DONE 등으로 감정이 처음 생기면 인트로 재생.
    // 러닝 영상 재생 중 DONE 도착 시 밑에서 인트로가 먼저 시작되지 않도록 가드.
    // 실제 시작은 _onRunningCompleted가 담당한다.
    if (!_hasEmotion(oldWidget) && _hasEmotion(widget) && !_runningActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startIntro());
    }
  }

  QuillController _buildReadOnlyController(String content) {
    final controller = QuillController(
      document: documentFromContent(content),
      selection: const TextSelection.collapsed(offset: 0),
    );
    controller.readOnly = true;
    return controller;
  }

  @override
  void didChangeMetrics() {
    // 리사이즈/회전 시 슬롯·Stack 좌표 재측정(안착 후에도 위치 유지).
    if (_hasEmotion(widget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_measureRestRect);
      });
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _settleController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  // ── 인트로 제어 ───────────────────────────────────────────────

  /// 인트로를 BIG부터 시작한다. 감정이 없으면 무시.
  /// 모션 줄이기 설정이면 BIG·SETTLE을 건너뛰고 바로 REST로.
  void _startIntro() {
    if (!mounted || !_hasEmotion(widget)) return;
    _dwellTimer?.cancel();
    _settleController.reset();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      setState(() => _phase = _IntroPhase.rest);
      return;
    }
    _measureRestRect(); // Stack은 이미 레이아웃 완료
    setState(() => _phase = _IntroPhase.big);
    _dwellTimer = Timer(_kDwell, _startSettle);
  }

  /// BIG → SETTLE 전환. 탭(건너뛰기) 또는 dwell 타이머가 호출.
  void _startSettle() {
    if (!mounted || _phase != _IntroPhase.big) return;
    _dwellTimer?.cancel();
    _measureRestRect(); // 최신 좌표 확보
    if (_restRect == null || _stackSize == null) {
      // 측정 실패 시 즉시 안착(애니메이션 생략).
      setState(() => _phase = _IntroPhase.rest);
      return;
    }
    setState(() => _phase = _IntroPhase.settle);
    _settleController.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _phase = _IntroPhase.rest);
    });
  }

  /// 안착 슬롯의 rect(Stack 로컬 좌표)와 Stack 크기를 측정해 저장한다.
  void _measureRestRect() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final slotBox = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || slotBox == null) return;
    if (!stackBox.hasSize || !slotBox.hasSize) return;
    final topLeft = slotBox.localToGlobal(Offset.zero, ancestor: stackBox);
    _restRect = topLeft & slotBox.size;
    _stackSize = stackBox.size;
  }

  /// BIG 단계 이모지 rect(중앙 정사각형). 측정 전엔 화면 크기로 폴백.
  Rect _bigRect() {
    final s = _stackSize ?? MediaQuery.sizeOf(context);
    final dim = math.min(s.width * 0.9, _kBigMax);
    return Rect.fromCenter(
      center: Offset(s.width / 2, s.height / 2),
      width: dim,
      height: dim,
    );
  }

  /// 현재 오버레이 이모지 rect — SETTLE 동안 BIG→안착으로 보간.
  Rect _currentOverlayRect() {
    final big = _bigRect();
    if (_phase == _IntroPhase.big || _restRect == null) return big;
    return Rect.lerp(big, _restRect!, _curved.value) ?? big;
  }

  /// 코멘트 불투명도 — BIG=0, SETTLE 후반 0→1, REST=1.
  double _commentOpacity() {
    switch (_phase) {
      case _IntroPhase.big:
        return 0;
      case _IntroPhase.rest:
        return 1;
      case _IntroPhase.settle:
        return ((_settleController.value - 0.5) / 0.5).clamp(0.0, 1.0);
    }
  }

  /// 단일 감정 영상 위젯(고정 [_videoKey]로 reparent 시 컨트롤러 유지).
  Widget _emotionVideo(double size) => EmotionVideo(
        key: _videoKey,
        emotionCode: widget.primaryEmotion,
        size: size,
        moodEmoji: widget.moodEmoji,
      );

  @override
  Widget build(BuildContext context) {
    final isPending = widget.analysisStatus == 'PENDING';
    final isDone = widget.analysisStatus == 'DONE';
    final showEmotion = isDone && widget.primaryEmotion != null;

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 날짜 라인 ──────────────────────────────────────────
          _DiaryHeader(dateText: widget.dateText),

          // ── 상태 배지 (DRAFT/FAILED만 표시, PENDING/DONE은 숨김) ─
          _buildStatusBadge(),

          // ── PENDING: 분석 중 카드 ─────────────────────────────
          if (isPending) ...[
            const SizedBox(height: AppSpacing.md),
            _AnalysisPendingCard(timedOut: widget.pollingTimedOut),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ── 읽기 전용 리치 본문 ──────────────────────────────
          Expanded(
            child: QuillEditor.basic(
              controller: _controller,
              config: QuillEditorConfig(
                padding: EdgeInsets.zero,
                showCursor: false,
                embedBuilders: const [DiaryImageEmbedBuilder()],
                // 종이 + 명조(serif) 본문 — 감정 텍스트색(있으면) 반영.
                customStyles: diaryPaperStyles(context, color: widget.textColor),
              ),
            ),
          ),

          // ── DONE: 글 하단 감정 안착 행(이모지 좌 + 코멘트 우, 박스 없음) ──
          if (showEmotion) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildRestingRow(),
          ],
          const SizedBox(height: AppSpacing.xl),

          // ── 하단 액션 버튼 ──────────────────────────────────
          _ActionButtons(onEdit: widget.onEdit, onDelete: widget.onDelete),
        ],
      ),
    );

    // 감정도 없고 러닝 오버레이도 없으면 콘텐츠만 반환한다.
    final needsStack = showEmotion || _runningVisible;
    if (!needsStack) return content;

    // 감정 인트로 또는 러닝 오버레이가 필요할 때 Stack으로 감싼다.
    return Stack(
      key: _stackKey,
      fit: StackFit.expand,
      children: [
        content,
        // DONE 시네마틱 인트로 — showEmotion 가드로 PENDING 때 호출 차단.
        if (showEmotion && _phase != _IntroPhase.rest) _buildIntroOverlay(),
        // 러닝 로딩 영상 오버레이 — 완료 시 페이드아웃 후 언마운트.
        if (_runningVisible)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _runningOpacity,
              duration: _kRunningFade,
              onEnd: _onRunningFadeEnd,
              child: _RunningIntroOverlay(onCompleted: _onRunningCompleted),
            ),
          ),
      ],
    );
  }

  /// 글 하단 감정 안착 행 — 좌: 영상 슬롯(REST에서 인라인 영상), 우: AI 제목·코멘트.
  Widget _buildRestingRow() {
    final inkColor = widget.textColor ?? AppColors.ink;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 좌측 슬롯 — BIG/SETTLE엔 빈 자리(영상은 오버레이), REST엔 영상 인라인.
        SizedBox(
          key: _slotKey,
          width: _kRestSize,
          height: _kRestSize,
          child: _phase == _IntroPhase.rest ? _emotionVideo(_kRestSize) : null,
        ),
        const SizedBox(width: AppSpacing.md),
        // 우측 AI 제목·코멘트 — 인트로 동안 페이드인.
        Expanded(
          child: AnimatedBuilder(
            animation: _settleController,
            builder: (context, child) => Opacity(
              opacity: _commentOpacity(),
              child: child,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.aiTitle != null)
                  Text(
                    widget.aiTitle!,
                    style: textTheme.titleMedium?.copyWith(
                      color: inkColor,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                if (widget.aiTitle != null && widget.aiComment != null)
                  const SizedBox(height: AppSpacing.xs),
                if (widget.aiComment != null)
                  Text(
                    widget.aiComment!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: inkColor,
                      height: 1.45,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 4,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 인트로 오버레이 — 콘텐츠 위 전체를 덮고, 큰 이모지를 중앙→안착으로 이동.
  /// 배경은 투명(종이 배경 비침). 탭하면 즉시 안착(건너뛰기).
  Widget _buildIntroOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _phase == _IntroPhase.big ? _startSettle : null,
        child: AnimatedBuilder(
          animation: _settleController,
          builder: (context, _) {
            final rect = _currentOverlayRect();
            return Stack(
              children: [
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  child: _emotionVideo(rect.width),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── 러닝 로딩 영상 제어 ──────────────────────────────────────

  /// PENDING으로 진입한 경우, 방문당 1회 러닝 로딩 영상을 시작한다.
  /// 폴링(3초) 리빌드는 같은 State를 유지하므로 _runningIntroPlayed 고정으로 재시작을 막는다.
  void _maybeStartRunningIntro() {
    if (!mounted || _runningIntroPlayed) return;
    if (widget.analysisStatus != 'PENDING') return;
    _runningIntroPlayed = true;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // 모션 줄이기 설정 시 영상을 생략하고 카드를 즉시 노출한다.
    if (reduceMotion) return;
    setState(() {
      _runningActive = true;
      _runningVisible = true;
      _runningOpacity = 1;
    });
  }

  /// 러닝 영상 완료 콜백.
  /// 이 시점에 이미 DONE이면 DONE 시네마틱 인트로로 핸드오프한다.
  void _onRunningCompleted() {
    if (!mounted) return;
    // 영상 재생이 끝난 뒤 이미 분석이 완료된 경우 시네마틱 인트로를 시작한다.
    if (widget.analysisStatus == 'DONE') _startIntro();
    // 페이드아웃 시작 — 밑의 카드 또는 인트로가 점차 드러난다.
    setState(() => _runningOpacity = 0);
  }

  /// 페이드아웃 종료 시 오버레이를 언마운트한다.
  void _onRunningFadeEnd() {
    if (!mounted || _runningOpacity != 0) return;
    setState(() {
      _runningVisible = false;
      _runningActive = false;
    });
  }

  /// DRAFT / FAILED일 때만 상태 배지를 반환한다.
  /// PENDING은 큰 카드가 대신하고, DONE은 글 하단 안착 행이 대신한다.
  Widget _buildStatusBadge() {
    final status = widget.analysisStatus;
    if (status == 'PENDING' || status == 'DONE') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: _AnalysisStatusBadge(status: status),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 날짜 + AI 헤더
// ──────────────────────────────────────────────────────────────

/// 상세 화면 상단의 날짜 헤더.
///
/// '2026년 6월 24일 (화)' 포맷의 [dateText]를 파싱해
/// 연/월(inkAlt 14px) + 일(WantedSans 800 36px) + 요일(inkAlt 600 20px)로
/// 계층형으로 표시한다.
class _DiaryHeader extends StatelessWidget {
  const _DiaryHeader({required this.dateText});

  final String dateText;

  /// '2026년 6월 24일 (화)' → { yearMonth: '2026년 6월', day: '24일', weekday: '화요일' }
  _DateParts _parse(String text) {
    final parts = text.trim().split(' ');
    if (parts.length >= 4) {
      final yearMonth = '${parts[0]} ${parts[1]}';
      final day = parts[2];
      // '(화)' → '화요일'
      final wkChar = parts[3].replaceAll('(', '').replaceAll(')', '');
      return _DateParts(
        yearMonth: yearMonth,
        day: day,
        weekday: '$wkChar요일',
      );
    }
    // 폴백: 그대로 표시
    return _DateParts(yearMonth: text, day: '', weekday: '');
  }

  @override
  Widget build(BuildContext context) {
    final p = _parse(dateText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 연/월 — inkAlt 14px 500
        if (p.yearMonth.isNotEmpty)
          Text(
            p.yearMonth,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.inkAlt,
            ),
          ),
        if (p.day.isNotEmpty) ...[
          const SizedBox(height: 2),
          // 일 — PoorStory 36px
          Text(
            p.day,
            style: const TextStyle(
              fontFamily: 'PoorStory',
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.36,
              height: 1.0,
            ),
          ),
        ],
        if (p.weekday.isNotEmpty) ...[
          const SizedBox(height: 2),
          // 요일 — inkAlt 600 20px
          Text(
            p.weekday,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.inkAlt,
            ),
          ),
        ],
      ],
    );
  }
}

/// [_DiaryHeader] 파싱 결과 DTO
class _DateParts {
  const _DateParts({
    required this.yearMonth,
    required this.day,
    required this.weekday,
  });
  final String yearMonth;
  final String day;
  final String weekday;
}

// ──────────────────────────────────────────────────────────────
// 상태 배지 (DRAFT / FAILED 전용)
// ──────────────────────────────────────────────────────────────

/// DRAFT·FAILED 상태 배지.
///
/// DRAFT: bgAlt 배경 전체 폭 카드 (연필 아이콘 + 제목 + 설명 문구).
/// FAILED: 헤어라인 pill 배지 (에러 아이콘 + '분석 실패').
/// PENDING·DONE은 각각 큰 카드·헤더가 대신하므로 이 위젯에서 제외.
class _AnalysisStatusBadge extends StatelessWidget {
  const _AnalysisStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == 'DRAFT') return _buildDraftCard(context);
    return _buildFailedBadge(context);
  }

  /// DRAFT — bgAlt 카드: 연필 아이콘 + '임시 저장' + 설명 문구
  Widget _buildDraftCard(BuildContext context) {
    return Semantics(
      label: '임시 저장된 기록입니다',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.bgAlt,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18, color: AppColors.ink),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '임시 저장',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '마저 작성하고 기록을 완성해 보세요',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// FAILED — 기존 헤어라인 pill 배지 유지
  Widget _buildFailedBadge(BuildContext context) {
    return Semantics(
      label: '감정 분석에 실패했습니다',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.hairline,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 14, color: AppColors.inkMuted),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '분석 실패',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 분석 중 카드 (PENDING일 때 본문 위에 표시)
// ──────────────────────────────────────────────────────────────

/// 감정 분석 진행 상태를 안내하는 카드.
///
/// [timedOut]이 false이면 회전하는 반짝이 아이콘(Icons.auto_awesome) + ETA 문구,
/// true이면 시계 아이콘 + "잠시 후 다시 확인해 주세요"로 전환된다.
class _AnalysisPendingCard extends StatefulWidget {
  const _AnalysisPendingCard({this.timedOut = false});

  final bool timedOut;

  @override
  State<_AnalysisPendingCard> createState() => _AnalysisPendingCardState();
}

class _AnalysisPendingCardState extends State<_AnalysisPendingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // 2초에 1회전 무한 반복 — 분석 진행 중 시각 피드백
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 아이콘: 진행 중=회전 반짝이, 타임아웃=시계
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: widget.timedOut
                  ? const Icon(
                      Icons.schedule_outlined,
                      color: AppColors.accent,
                      size: 20,
                    )
                  : RotationTransition(
                      turns: _rotationController,
                      child: const Icon(
                        Icons.auto_awesome,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.timedOut ? '잠시 후 다시 확인해 주세요' : '감정을 담는 중이에요',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!widget.timedOut) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      kAnalysisEtaText,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '이 화면을 벗어나도 분석은 계속돼요',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 러닝 로딩 영상 오버레이 (PENDING 진입 시 전체화면 1회 재생)
// ──────────────────────────────────────────────────────────────

/// 감정 분석 PENDING 진입 시 전체화면에 1회 재생되는 로딩 영상 오버레이.
///
/// 영상 재생이 완료되면 [onCompleted]를 호출한다. 에셋 로드 실패 시에도
/// 즉시 [onCompleted]를 호출해 뒤에 있는 카드가 자연스럽게 드러나도록 폴백한다.
class _RunningIntroOverlay extends StatefulWidget {
  const _RunningIntroOverlay({required this.onCompleted});

  /// 영상 재생 완료(또는 폴백) 시 호출되는 콜백.
  final VoidCallback onCompleted;

  @override
  State<_RunningIntroOverlay> createState() => _RunningIntroOverlayState();
}

class _RunningIntroOverlayState extends State<_RunningIntroOverlay> {
  late final VideoPlayerController _controller;

  /// 영상 초기화 완료 여부 — false이면 흰 배경으로 깜빡임 방지.
  bool _ready = false;

  /// onCompleted 중복 호출 방지 플래그.
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    // 음소거: 웹 자동재생 정책 충족 + 배경 소음 방지.
    // setLooping 미호출 = 1회 재생 후 자동 정지.
    _controller = VideoPlayerController.asset(kRunningIntroAsset)
      ..setVolume(0);

    _controller.initialize().then((_) {
      if (!mounted) return;
      // 완료 감지 리스너 등록 후 재생 시작.
      _controller.addListener(_checkCompleted);
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object _) {
      // 에셋 실패·미존재 시 즉시 완료 폴백 — 뒤의 카드가 바로 드러난다.
      _fireOnce();
    });
  }

  /// 영상 재생 종료 감지.
  /// isCompleted 플래그 또는 position≥duration+정지 조합으로 완료를 판단한다.
  void _checkCompleted() {
    final v = _controller.value;
    if (!v.isInitialized || _fired) return;
    if (v.isCompleted ||
        (v.duration > Duration.zero &&
            v.position >= v.duration &&
            !v.isPlaying)) {
      _fireOnce();
    }
  }

  /// 완료 콜백을 정확히 1회만 호출한다.
  void _fireOnce() {
    if (_fired) return;
    _fired = true;
    widget.onCompleted();
  }

  @override
  void dispose() {
    _controller.removeListener(_checkCompleted);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 초기화 전엔 흰 배경으로 채워 검은 박스 깜빡임을 방지한다.
    if (!_ready) {
      return const ColoredBox(
        color: AppColors.surface,
        child: SizedBox.expand(),
      );
    }

    // 흰 배경 위 마스코트 영상 — cover로 화면을 꽉 채우면 과하게 확대·크롭되어
    // 어색하므로, contain으로 마스코트 전체가 잘리지 않고 중앙에 자연스러운
    // 크기로 보이게 한다(배경이 surface와 동일해 여백이 티나지 않는다).
    return ColoredBox(
      color: AppColors.surface,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 하단 액션 버튼
// ──────────────────────────────────────────────────────────────

/// 하단 액션 버튼 영역.
///
/// DRAFT([onEdit] != null):
///   [이어 쓰기 (FilledButton, 확장)] + [휴지통 아이콘 OutlinedButton 52px]
///
/// 확정([onEdit] == null):
///   [닫기 (OutlinedButton, 확장)] + [휴지통 아이콘 OutlinedButton 52px]
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    this.onEdit,
    required this.onDelete,
  });

  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  static final BorderRadius _buttonRadius =
      BorderRadius.circular(AppRadius.button);

  @override
  Widget build(BuildContext context) {
    final isDraft = onEdit != null;

    return Row(
      children: [
        // 주 액션 버튼 — DRAFT='이어 쓰기'(solid), 확정='닫기'(outlined)
        Expanded(
          child: isDraft
              ? FilledButton.icon(
                  onPressed: onEdit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('이어 쓰기'),
                )
              : OutlinedButton(
                  // TODO: 로직 연결 지점 — Navigator.of(context).pop() 처리
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size(0, 52),
                    side: const BorderSide(color: AppColors.hairline, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
                  ),
                  child: const Text('닫기'),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // 삭제 — 아이콘 전용 OutlinedButton 52×52dp
        SizedBox(
          width: 52,
          height: 52,
          child: OutlinedButton(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: EdgeInsets.zero,
              side: const BorderSide(color: AppColors.error, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: _buttonRadius),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: const Icon(Icons.delete_outline, size: 20),
          ),
        ),
      ],
    );
  }
}
