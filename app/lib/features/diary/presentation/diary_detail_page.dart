import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/api_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
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
/// 상세 배경은 감정과 무관하게 항상 흰색으로 통일한다. 감정 동적 배경 테마는 제거됐고
/// (Task 025), 감정은 감정 칩으로만 표시된다.
///
/// ## 폴링 없음
/// 감정 분석을 끈(Task 024) 뒤 확정은 즉시 DONE 이므로 PENDING 자동 갱신 폴링을 제거했다.
/// (감정 분석 flag를 켜면 PENDING이 생길 수 있으나, 그 경우 화면 재진입/새로고침으로 갱신한다.)
class DiaryDetailPage extends ConsumerStatefulWidget {
  const DiaryDetailPage({super.key, required this.diaryId});

  final String diaryId;

  @override
  ConsumerState<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends ConsumerState<DiaryDetailPage> {
  String _dateText(DateTime d) =>
      '${d.year}년 ${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
      await ref.read(diaryRepositoryProvider).delete(id);
      ref.invalidate(monthlySummaryProvider);
      ref.invalidate(monthDiariesProvider);
      ref.invalidate(diaryByDateProvider);
      if (!context.mounted) return;
      showAppSnackBar(context, '삭제했어요');
      context.go('/calendar');
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

    final async = ref.watch(diaryByIdProvider(id));
    final diary = async.asData?.value;

    return Scaffold(
      // 상세 배경: 감정과 무관하게 항상 흰색으로 통일.
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
            // 사용자 감정(프리셋/커스텀) — 감정 칩 표시용.
            primaryEmotion: d.primaryEmotion,
            emotionLabel: d.emotionLabel,
          ),
        ),
      ),
    );
  }
}
