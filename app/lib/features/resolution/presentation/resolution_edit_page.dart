import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/resolution.dart';
import 'providers/resolution_providers.dart';

const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 작심삼일 수정 화면.
///
/// [id]로 기존 결심을 조회해 제목·알림 시각만 편집한다(진행 중 결심 전용).
/// 시작일은 종료일·3일 체크 재계산 복잡도 때문에 수정 대상이 아니며 읽기 전용으로만 보여준다.
/// 시작일을 바꾸려면 삭제 후 재작성한다. 제출은 [UpdateResolutionController]가 처리한다.
class ResolutionEditPage extends ConsumerWidget {
  const ResolutionEditPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(resolutionByIdProvider(id));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('작심삼일 수정'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorView(
            message: '작심삼일을 불러오지 못했어요',
            onRetry: () => ref.invalidate(resolutionByIdProvider(id)),
          ),
          data: (r) => _EditForm(resolution: r),
        ),
      ),
    );
  }
}

/// 기존 결심 값으로 프리필된 수정 폼.
class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.resolution});

  final Resolution resolution;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;

  /// 매일 알림 시각. null이면 '알림 없음'.
  late TimeOfDay? _reminderTime;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.resolution.title);
    _reminderTime = widget.resolution.reminderTimeOfDay;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  DateTime get _startDate => widget.resolution.startDate;
  DateTime get _endDate => widget.resolution.endDate;

  String _shortDate(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  /// TimeOfDay → 'HH:mm' 문자열.
  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? const TimeOfDay(hour: 21, minute: 0),
    );
    if (picked != null) {
      setState(() => _reminderTime = picked);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    try {
      await ref.read(updateResolutionControllerProvider.notifier).submit(
            widget.resolution.id,
            title: _titleController.text.trim(),
            reminderTime:
                _reminderTime != null ? _formatTime(_reminderTime!) : null,
          );
      if (!mounted) return;
      showAppSnackBar(context, '작심삼일을 수정했어요');
      context.pop();
    } on Failure catch (f) {
      if (!mounted) return;
      showAppSnackBar(context, f.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '수정에 실패했어요. 다시 시도해주세요.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 컨트롤러 AsyncValue를 구독해 제출 진행/버튼 로딩을 표현한다.
    final submitting = ref.watch(updateResolutionControllerProvider).isLoading;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── 제목 ──
          const _FieldLabel('무엇에 도전할까요?'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _titleController,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '예: 매일 아침 10분 스트레칭',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? '도전할 내용을 입력해주세요'
                : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          // ── 시작일(읽기 전용) ──
          const _FieldLabel('기간'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_shortDate(_startDate)} ~ ${_shortDate(_endDate)} · 3일간',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '시작일은 수정할 수 없어요. 날짜를 바꾸려면 삭제 후 새로 만들어주세요.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          // ── 알림 시각 ──
          const _FieldLabel('매일 알림'),
          const SizedBox(height: AppSpacing.sm),
          _PickerTile(
            icon: Icons.notifications_none,
            label: _reminderTime != null
                ? '매일 ${_formatTime(_reminderTime!)} 알림'
                : '알림 없음',
            onTap: _pickReminderTime,
            // 알림이 설정되어 있으면 해제 버튼 노출.
            trailing: _reminderTime != null
                ? IconButton(
                    tooltip: '알림 해제',
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.inkMuted,
                    onPressed: () => setState(() => _reminderTime = null),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.xl),
          // ── 저장 버튼 ──
          FilledButton(
            onPressed: submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            child: submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: AppColors.surface,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    '저장하기',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 폼 섹션 라벨.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}

/// 탭하면 피커를 여는 타일(시각 선택).
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgAlt,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.inkAlt),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
