import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'providers/resolution_providers.dart';

const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 작심삼일 생성 화면.
///
/// 라우트 쿼리 [date](yyyy-MM-dd)로 초기 시작일을 받는다(없으면 오늘). 제목·시작일·
/// 알림시각을 입력받아 [CreateResolutionController]로 생성한다. 종료일은 서버가
/// `시작일 + 2`로 파생하므로, 화면에서는 3일 기간 안내만 보여준다.
class ResolutionNewPage extends ConsumerStatefulWidget {
  const ResolutionNewPage({super.key, this.date});

  /// YYYY-MM-DD. null이면 오늘로 시작.
  final String? date;

  @override
  ConsumerState<ResolutionNewPage> createState() => _ResolutionNewPageState();
}

class _ResolutionNewPageState extends ConsumerState<ResolutionNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  /// 시작일(연·월·일만 의미). 오늘 이전 불가.
  late DateTime _startDate;

  /// 매일 알림 시각. null이면 '알림 없음'. 기본 21:00.
  TimeOfDay? _reminderTime = const TimeOfDay(hour: 21, minute: 0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parsed = widget.date != null ? DateTime.tryParse(widget.date!) : null;
    final base = parsed != null
        ? DateTime(parsed.year, parsed.month, parsed.day)
        : today;
    // 과거로 직접 진입(라우트 조작 등) 시 오늘로 클램프.
    _startDate = base.isBefore(today) ? today : base;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  DateTime get _endDate => _startDate.add(const Duration(days: 2));

  String _shortDate(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  /// TimeOfDay → 'HH:mm' 문자열.
  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── 입력 핸들러 ────────────────────────────────────────────────

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _startDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

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
      await ref.read(createResolutionControllerProvider.notifier).submit(
            title: _titleController.text.trim(),
            startDate: _startDate,
            reminderTime:
                _reminderTime != null ? _formatTime(_reminderTime!) : null,
          );
      if (!mounted) return;
      showAppSnackBar(context, '작심삼일을 시작했어요');
      context.pop();
    } on Failure catch (f) {
      if (!mounted) return;
      showAppSnackBar(context, f.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '생성에 실패했어요. 다시 시도해주세요.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 컨트롤러 AsyncValue를 구독해 제출 진행/버튼 로딩을 표현한다.
    final submitting = ref.watch(createResolutionControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('작심삼일 시작'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── 제목 ──
              const _FieldLabel('무엇에 도전할까요?'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _titleController,
                maxLength: 30,
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
              // ── 시작일 ──
              const _FieldLabel('언제 시작할까요?'),
              const SizedBox(height: AppSpacing.sm),
              _PickerTile(
                icon: Icons.calendar_today_outlined,
                label: _shortDate(_startDate),
                onTap: _pickStartDate,
              ),
              const SizedBox(height: AppSpacing.sm),
              // 3일 기간 안내.
              Text(
                '${_shortDate(_startDate)} ~ ${_shortDate(_endDate)} · 3일간',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
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
              // ── 생성 버튼 ──
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
                        '작심삼일 시작하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
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

/// 탭하면 피커를 여는 타일(날짜·시각 선택 공용).
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
