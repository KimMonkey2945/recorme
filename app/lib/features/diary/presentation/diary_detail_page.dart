import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/api_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/diary_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/share_options_sheet.dart';
import '../../../shared/widgets/visibility_change_sheet.dart';
import '../../../shared/widgets/visibility_segment.dart';
import '../data/dto/diary_dto.dart';
import 'providers/diary_providers.dart';
import 'widgets/diary_detail_view.dart';

const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 기록 상세 화면.
///
/// id로 단건을 조회해 전체 내용을 보여주고, 수정(에디터 이동)·삭제(확인
/// 다이얼로그 후 소프트 삭제 → 메인 복귀)를 제공한다. 표현은 [DiaryDetailView].
///
/// ## 배경
/// 상세 배경은 감정과 무관하게 항상 흰색으로 통일한다. 감정 이모지(영상)의 흰 배경과
/// 페이지 배경 사이에 이질감이 생기지 않도록, 이전의 감정색 틴트 배경은 제거했다.
/// 감정 팔레트는 본문·코멘트 텍스트 색상 등에만 사용한다.
///
/// ## PENDING 자동 갱신
/// analysisStatus가 'PENDING'이면 3초마다 [diaryByIdProvider]를 invalidate해
/// 서버에서 최신 상태를 재조회한다. DONE/FAILED가 되면 타이머를 중단한다.
/// 안전 상한은 누적 60회(약 3분). 초과 시 타이머를 멈추고 안내 메시지를 표시한다.
class DiaryDetailPage extends ConsumerStatefulWidget {
  const DiaryDetailPage({super.key, required this.diaryId});

  final String diaryId;

  @override
  ConsumerState<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends ConsumerState<DiaryDetailPage> {
  /// 분석 중 자동 갱신 타이머.
  Timer? _pollingTimer;

  /// 누적 폴링 횟수. 상한(60회 × 3초 = 3분) 도달 시 타이머 중단.
  int _pollCount = 0;

  /// 폴링 1회 간격.
  static const Duration _pollInterval = Duration(seconds: 3);

  /// 폴링 최대 횟수(3분 상한).
  static const int _maxPollCount = 60;

  /// 폴링 상한 초과 여부. true이면 DiaryDetailView에서 "잠시 후 확인" 안내 표시.
  bool _pollingTimedOut = false;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  String _dateText(DateTime d) =>
      '${d.year}년 ${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── 폴링 제어 ─────────────────────────────────────────────────

  /// PENDING 상태이면 폴링을 시작한다. 이미 실행 중이면 무시(멱등).
  void _startPolling(int id) {
    if (_pollingTimer != null) return;
    _pollCount = 0;
    _pollingTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) {
        _pollingTimer?.cancel();
        _pollingTimer = null;
        return;
      }
      _pollCount++;
      if (_pollCount >= _maxPollCount) {
        _pollingTimer?.cancel();
        _pollingTimer = null;
        setState(() => _pollingTimedOut = true);
        return;
      }
      ref.invalidate(diaryByIdProvider(id));
    });
  }

  /// 폴링 타이머를 중단한다. 이미 없으면 무시.
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ── 삭제 처리 ─────────────────────────────────────────────────

  Future<void> _handleDelete(BuildContext context, int id) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '일기 삭제',
      message: '이 일기를 삭제할까요? 삭제하면 같은 날짜에 다시 쓸 수 있어요.',
      confirmLabel: '삭제',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      _stopPolling();
      await ref.read(diaryRepositoryProvider).delete(id);
      ref.invalidate(monthlySummaryProvider);
      ref.invalidate(monthDiariesProvider);
      ref.invalidate(diaryByDateProvider);
      if (!context.mounted) return;
      showAppSnackBar(context, '삭제했어요');
      context.go('/');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, '삭제에 실패했어요', isError: true);
    }
  }

  // ── 공개범위 변경 / 공유 ─────────────────────────────────────

  /// 공개범위 변경 시트 → 선택 시 PATCH → 관련 캐시 갱신.
  Future<void> _changeVisibility(int id, Diary diary) async {
    final selected =
        await showVisibilityChangeSheet(context, current: diary.visibility);
    if (selected == null || selected == diary.visibility || !mounted) return;
    try {
      await ref.read(diaryRepositoryProvider).changeVisibility(id, selected);
      ref.invalidate(diaryByIdProvider(id));
      ref.invalidate(monthlySummaryProvider);
      ref.invalidate(monthDiariesProvider);
      if (mounted) {
        showAppSnackBar(context, '공개범위를 ${VisibilityAssets.labelOf(selected)}로 바꿨어요');
      }
    } on Failure catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    }
  }

  /// 공유 시트(PRIVATE이 아닐 때만 호출됨). 공유 링크 복사/외부 공유.
  void _share(Diary diary) {
    final token = diary.shareToken;
    if (token == null) return;
    showShareOptionsSheet(context, shareUrl: ApiConfig.sharedUrl(token));
  }

  /// AppBar 우측 액션(공개범위 변경 + 공유). 데이터 로드 후에만 노출.
  List<Widget> _actions(int id, Diary? diary) {
    if (diary == null) return const [];
    final isPrivate = diary.visibility == 'PRIVATE';
    return [
      IconButton(
        icon: Icon(VisibilityAssets.iconOf(diary.visibility)),
        tooltip: '공개범위 변경',
        onPressed: () => _changeVisibility(id, diary),
      ),
      IconButton(
        icon: const Icon(Icons.share_outlined),
        tooltip: isPrivate ? '친구 공개 이상으로 바꾼 뒤 공유할 수 있어요' : '공유하기',
        onPressed: isPrivate ? null : () => _share(diary),
      ),
    ];
  }

  // ── 빌드 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(widget.diaryId) ?? -1;

    // 상태 변화를 감지해 폴링을 제어한다.
    ref.listen<AsyncValue<Diary>>(diaryByIdProvider(id), (_, next) {
      final status = next.asData?.value.analysisStatus;
      if (status == 'PENDING') {
        _startPolling(id);
      } else if (status != null) {
        _stopPolling();
      }
    });

    final async = ref.watch(diaryByIdProvider(id));

    // 초기 캐시 히트(PENDING) 처리 — ref.listen은 변화가 있을 때만 호출되므로
    // 첫 빌드에서 이미 PENDING이면 프레임 종료 후 폴링을 시작한다(build는 부수효과 없이 유지).
    if (async.asData?.value.analysisStatus == 'PENDING') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startPolling(id);
      });
    }

    // 감정 팔레트 — 본문·코멘트 텍스트/포인트 색상에만 사용(배경엔 미적용).
    final diary = async.asData?.value;
    final palette = (diary?.hasTheme == true)
        ? DiaryTheme.fromEmotion(diary!.primaryEmotion)
        : null;

    return Scaffold(
      // 상세 배경: 감정과 무관하게 흰색으로 통일(이모지 영상 흰 배경과 일치).
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        // 타이틀 없음 — 날짜·AI 제목이 본문 헤더에서 담당.
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: _actions(id, diary),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorView(
            message: '일기를 불러오지 못했어요',
            onRetry: () => ref.invalidate(diaryByIdProvider(id)),
          ),
          data: (d) => DiaryDetailView(
            dateText: _dateText(d.writtenDate),
            content: d.content,
            analysisStatus: d.analysisStatus,
            pollingTimedOut: _pollingTimedOut,
            // 확정 기록(isDraft=false)은 수정 불가 → null 전달로 수정 버튼 숨김.
            onEdit: d.isDraft
                ? () async {
                    await context.push(
                      '/editor?date=${_dateParam(d.writtenDate)}',
                    );
                    ref.invalidate(diaryByIdProvider(id));
                  }
                : null,
            onDelete: () => _handleDelete(context, id),
            // 감정 코드 전달 — 무드 카드 마스코트 이미지 선택용(DONE 시에만 비-null).
            primaryEmotion: d.hasTheme ? d.primaryEmotion : null,
            // 팔레트 색상 전달 — DONE 아니면 null이므로 DiaryDetailView 기본값 사용.
            // moodCardColor는 무드 카드 채움색(감정 배경색). 페이지 배경엔 쓰지 않음.
            moodCardColor: palette?.backgroundColor,
            textColor: palette?.textColor,
            accentColor: palette?.accentColor,
            // 이모지·코멘트·제목은 API 값 그대로 사용 (LLM이 잘 생성함).
            moodEmoji: d.moodEmoji,
            aiComment: d.aiComment,
            aiTitle: d.aiTitle,
          ),
        ),
      ),
    );
  }
}
