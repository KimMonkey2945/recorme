import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import 'providers/diary_providers.dart';
import 'widgets/diary_detail_view.dart';

const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 일기 상세 화면.
///
/// id로 단건을 조회해 전체 내용을 보여주고, 수정(에디터 이동)·삭제(확인
/// 다이얼로그 후 소프트 삭제 → 메인 복귀)를 제공한다. 표현은 [DiaryDetailView].
class DiaryDetailPage extends ConsumerWidget {
  const DiaryDetailPage({super.key, required this.diaryId});

  final String diaryId;

  String _dateText(DateTime d) =>
      '${d.year}년 ${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(diaryId) ?? -1;
    final async = ref.watch(diaryByIdProvider(id));

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('일기'),
        ),
        body: SafeArea(
          child: async.when(
            loading: () => const LoadingView(),
            error: (_, _) => ErrorView(
              message: '일기를 불러오지 못했어요',
              onRetry: () => ref.invalidate(diaryByIdProvider(id)),
            ),
            data: (diary) => DiaryDetailView(
              dateText: _dateText(diary.writtenDate),
              content: diary.content,
              analysisStatus: diary.analysisStatus,
              onEdit: () async {
                await context.push('/editor?date=${_dateParam(diary.writtenDate)}');
                ref.invalidate(diaryByIdProvider(id));
              },
              onDelete: () => _handleDelete(context, ref, id),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref, int id) async {
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
      ref.invalidate(diaryByDateProvider);
      if (!context.mounted) return;
      showAppSnackBar(context, '삭제했어요');
      context.go('/'); // 메인(캘린더) 복귀
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, '삭제에 실패했어요', isError: true);
    }
  }
}
