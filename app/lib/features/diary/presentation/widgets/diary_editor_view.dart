import 'package:flutter/material.dart';
import 'package:record/core/theme/app_colors.dart';
import 'package:record/core/theme/app_spacing.dart';

/// 일기 작성/수정 화면의 순수 표현 위젯.
///
/// Scaffold·AppBar·배경 그라데이션은 상위 페이지가 담당하며,
/// 이 위젯은 에디터 콘텐츠 영역(날짜 칩 + 텍스트 입력 + 버튼 바)만 책임진다.
///
/// **사용 예시 (DiaryEditorPage 내부)**
/// ```dart
/// DiaryEditorView(
///   dateText: '2026년 6월 24일',
///   saving: state.isSaving,
///   onSave: (content) => ref.read(diaryNotifier.notifier).save(date, content),
///   onCancel: context.pop,
/// )
/// ```
class DiaryEditorView extends StatefulWidget {
  const DiaryEditorView({
    super.key,
    required this.dateText,
    this.initialContent,
    required this.saving,
    required this.onSave,
    required this.onCancel,
  });

  /// 표시용 날짜 문자열 (예: '2026년 6월 24일') — 읽기 전용 칩에 표시됩니다.
  final String dateText;

  /// 수정 모드일 때 텍스트 필드를 미리 채울 내용. null이면 신규 작성.
  final String? initialContent;

  /// 저장 요청이 진행 중이면 true — 저장 버튼을 비활성 + 로딩 인디케이터로 전환합니다.
  final bool saving;

  /// 저장 버튼 탭 시 호출됩니다. 트림된 입력 텍스트를 전달합니다.
  // TODO: 로직 연결 지점 — 실제 upsert 호출은 상위 페이지/Riverpod notifier에서 처리.
  final void Function(String content) onSave;

  /// 취소 버튼 탭 시 호출됩니다.
  // TODO: 로직 연결 지점 — 뒤로가기·dirty 감지 등은 상위 페이지에서 처리.
  final VoidCallback onCancel;

  @override
  State<DiaryEditorView> createState() => _DiaryEditorViewState();
}

class _DiaryEditorViewState extends State<DiaryEditorView> {
  late final TextEditingController _controller;

  /// 저장 버튼 활성/비활성 판단을 위한 입력 비어 있는지 여부.
  bool _isEmpty = true;

  @override
  void initState() {
    super.initState();
    // 수정 모드인 경우 initialContent로 컨트롤러 초기화.
    final initial = widget.initialContent ?? '';
    _controller = TextEditingController(text: initial);
    _isEmpty = initial.trim().isEmpty;
    _controller.addListener(_onTextChanged);
  }

  /// 텍스트 변경 감지 → isEmpty 상태 갱신 → 저장 버튼 활성/비활성 반영.
  void _onTextChanged() {
    final empty = _controller.text.trim().isEmpty;
    if (empty != _isEmpty) {
      setState(() => _isEmpty = empty);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  /// 저장 가능 여부: 내용이 있고(비어 있지 않고) 저장 중이 아닐 때만 true.
  bool get _canSave => !_isEmpty && !widget.saving;

  void _handleSave() {
    if (!_canSave) return;
    widget.onSave(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 날짜 읽기 전용 칩 ────────────────────────────────────
          _DateChip(dateText: widget.dateText),
          const SizedBox(height: AppSpacing.lg),
          // ── 본문 텍스트 입력 영역 ────────────────────────────────
          Expanded(
            child: _DiaryTextField(
              controller: _controller,
              enabled: !widget.saving,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // ── 하단 버튼 바 ─────────────────────────────────────────
          _BottomButtonBar(
            saving: widget.saving,
            canSave: _canSave,
            onSave: _handleSave,
            onCancel: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 날짜 읽기 전용 칩
// ─────────────────────────────────────────────────────────────────────────────

/// 선택된 날짜를 표시하는 읽기 전용 Pill 칩.
/// accentSoft 배경 + 캘린더 아이콘으로 편집 불가 상태임을 시각적으로 드러낸다.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.dateText});

  final String dateText;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: AppColors.accent,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              dateText,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 본문 멀티라인 텍스트 필드
// ─────────────────────────────────────────────────────────────────────────────

/// 일기 본문 입력 영역.
/// [expands] + [maxLines] null 조합으로 Expanded 안에서 전체 높이를 채운다.
/// 포커스 시 hairline → accent 컬러로 테두리가 전환된다.
class _DiaryTextField extends StatelessWidget {
  const _DiaryTextField({
    required this.controller,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool enabled;

  /// 카드 반경과 일치하는 상수 BorderRadius — const 생성자에서 사용.
  static const BorderRadius _kCardRadius =
      BorderRadius.all(Radius.circular(AppRadius.card));

  @override
  Widget build(BuildContext context) {
    final bodyLarge = Theme.of(context).textTheme.bodyLarge;

    return DecoratedBox(
      // TextField 뒤에 그림자 레이어를 추가한다.
      // DecoratedBox는 자식 크기를 변경하지 않으므로 레이아웃 영향 없음.
      decoration: const BoxDecoration(
        borderRadius: _kCardRadius,
        boxShadow: [
          BoxShadow(
            color: Color(0x08232228), // AppColors.ink ~3% 투명도
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: bodyLarge?.copyWith(
          color: AppColors.ink,
          height: 1.75, // 넉넉한 행간 — "조용한 일기장" 필기 느낌
        ),
        decoration: InputDecoration(
          hintText: '오늘 하루를 기록해보세요',
          hintStyle: bodyLarge?.copyWith(
            color: AppColors.inkMuted,
            height: 1.75,
          ),
          contentPadding: const EdgeInsets.all(AppSpacing.xl),
          // 기본 테두리 (fallback)
          border: const OutlineInputBorder(
            borderRadius: _kCardRadius,
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          // 활성 상태 — hairline 테두리
          enabledBorder: const OutlineInputBorder(
            borderRadius: _kCardRadius,
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          // 포커스 상태 — accent 색상, 1.5dp 두께
          focusedBorder: const OutlineInputBorder(
            borderRadius: _kCardRadius,
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
          // 비활성 상태 (saving 중) — hairline 유지, 시각적 연속성 보장
          disabledBorder: const OutlineInputBorder(
            borderRadius: _kCardRadius,
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          filled: true,
          fillColor: AppColors.surface,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 하단 버튼 바 (취소 + 저장)
// ─────────────────────────────────────────────────────────────────────────────

/// 취소(OutlinedButton) + 저장(FilledButton) 가로 배치.
/// 저장 버튼이 남은 가로 공간을 모두 차지해 더 돋보이도록 한다.
class _BottomButtonBar extends StatelessWidget {
  const _BottomButtonBar({
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.onCancel,
  });

  final bool saving;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  /// 버튼 고정 높이 — 최소 탭 영역(48dp) 초과 보장.
  static const double _kButtonHeight = 52;

  /// 버튼 공통 모양 — button 반경(14dp), Pill에 가까운 둥근 형태.
  static const OutlinedBorder _kButtonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── 취소 버튼 ────────────────────────────────────────────
        SizedBox(
          height: _kButtonHeight,
          child: OutlinedButton(
            onPressed: saving ? null : onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.inkMuted,
              side: const BorderSide(color: AppColors.hairline),
              shape: _kButtonShape,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            ),
            child: const Text('취소'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // ── 저장 버튼 (나머지 가로 공간 점유) ───────────────────────
        Expanded(
          child: SizedBox(
            height: _kButtonHeight,
            child: FilledButton(
              onPressed: canSave ? onSave : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                // 비활성(내용 없거나 saving 중): accentSoft로 부드럽게 처리
                disabledBackgroundColor: AppColors.accentSoft,
                shape: _kButtonShape,
              ),
              // saving 중: 텍스트 대신 로딩 인디케이터 표시 (레이아웃 점프 방지)
              child: saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.surface),
                      ),
                    )
                  : const Text('저장'),
            ),
          ),
        ),
      ],
    );
  }
}
