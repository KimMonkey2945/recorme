import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/loading_view.dart';
import 'providers/diary_providers.dart';
import 'widgets/diary_editor_view.dart';

/// 일기 작성/수정 화면.
///
/// 라우트 쿼리 [date](yyyy-MM-dd)로 대상 날짜를 받는다. 해당 날짜에 일기가
/// 있으면 수정 모드(기존 내용 프리필), 없으면 신규 작성. 저장은 upsert.
/// 표현은 [DiaryEditorView], 데이터/저장 로직은 이 래퍼가 담당.
class DiaryEditorPage extends ConsumerStatefulWidget {
  const DiaryEditorPage({super.key, this.date});

  /// YYYY-MM-DD. null이면 오늘 날짜로 신규 작성.
  final String? date;

  @override
  ConsumerState<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends ConsumerState<DiaryEditorPage> {
  late final DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final parsed = widget.date != null ? DateTime.tryParse(widget.date!) : null;
    final base = parsed ?? DateTime.now();
    _date = DateTime(base.year, base.month, base.day);
  }

  String get _dateText => '${_date.year}년 ${_date.month}월 ${_date.day}일';

  Future<void> _onSave(String content) async {
    if (content.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(diaryRepositoryProvider)
          .upsert(date: _date, content: content);
      // 캘린더 dot·날짜/단건 캐시 갱신
      ref.invalidate(monthlySummaryProvider);
      ref.invalidate(diaryByDateProvider);
      ref.invalidate(diaryByIdProvider);
      if (!mounted) return;
      showAppSnackBar(context, '저장했어요');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '저장에 실패했어요', isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 기존 일기 존재 여부 → 수정/신규 모드 및 프리필 결정
    final existing = ref.watch(diaryByDateProvider(_date));
    final isEdit = existing.asData?.value != null;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(isEdit ? '일기 수정' : '일기 쓰기'),
        ),
        body: SafeArea(
          child: existing.when(
            loading: () => const LoadingView(),
            error: (_, _) => DiaryEditorView(
              dateText: _dateText,
              saving: _saving,
              onSave: _onSave,
              onCancel: () => context.pop(),
            ),
            data: (diary) => DiaryEditorView(
              dateText: _dateText,
              initialContent: diary?.content,
              saving: _saving,
              onSave: _onSave,
              onCancel: () => context.pop(),
            ),
          ),
        ),
      ),
    );
  }
}
