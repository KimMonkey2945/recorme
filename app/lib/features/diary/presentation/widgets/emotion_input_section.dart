import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/emotion_labels.dart';
import '../../../../core/theme/emotion_palette.dart';

/// 작성기 감정 입력 섹션(Task 025 — 감정 사용자 직접 입력).
///
/// 감정 LLM 분석을 제거한 자리에, 사용자가 **프리셋 6종 중 하나를 고르거나** 또는
/// **직접 입력(자유 텍스트 ≤20자)** 하는 위젯이다. 프리셋과 직접 입력은 **상호 배타**이며
/// (동시 선택 불가 → 백엔드 `EMOTION_CONFLICT` 사전 차단), 둘 다 비워도 된다(감정은 선택 사항).
///
/// 상태는 이 위젯이 소유하고, 바뀔 때마다 [onChanged]로 `(emotion, emotionLabel)`을 올려준다
/// — 항상 둘 중 최대 하나만 non-null이다.
class EmotionInputSection extends StatefulWidget {
  const EmotionInputSection({
    super.key,
    required this.onChanged,
    this.initialEmotion,
    this.initialEmotionLabel,
    this.recentLabels = const [],
  });

  /// `(emotion, emotionLabel)` 변경 콜백. 상호 배타라 최대 하나만 non-null.
  final void Function(String? emotion, String? emotionLabel) onChanged;

  /// 초기 프리셋 코드(수정 진입 시).
  final String? initialEmotion;

  /// 초기 커스텀 라벨(수정 진입 시).
  final String? initialEmotionLabel;

  /// 최근 사용한 커스텀 감정 라벨(추천 칩).
  final List<String> recentLabels;

  @override
  State<EmotionInputSection> createState() => _EmotionInputSectionState();
}

class _EmotionInputSectionState extends State<EmotionInputSection> {
  /// 직접 입력 모드 여부(프리셋과 배타).
  late bool _customMode;

  /// 선택된 프리셋 코드(없으면 null).
  String? _selectedCode;

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialEmotion;
    _customMode = widget.initialEmotionLabel != null &&
        widget.initialEmotionLabel!.isNotEmpty;
    _controller = TextEditingController(text: widget.initialEmotionLabel ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPreset(String code) {
    setState(() {
      if (_selectedCode == code) {
        // 재탭 → 해제(감정 미입력).
        _selectedCode = null;
      } else {
        _selectedCode = code;
        // 프리셋 선택 시 직접 입력 해제(상호 배타).
        _customMode = false;
        _controller.clear();
      }
    });
    widget.onChanged(_selectedCode, null);
  }

  void _enterCustomMode() {
    setState(() {
      _customMode = true;
      _selectedCode = null; // 직접 입력 진입 시 프리셋 해제(상호 배타).
    });
    _emitCustom();
  }

  void _onCustomChanged(String _) => _emitCustom();

  void _emitCustom() {
    final text = _controller.text.trim();
    widget.onChanged(null, text.isEmpty ? null : text);
  }

  void _pickRecent(String label) {
    setState(() {
      _customMode = true;
      _selectedCode = null;
      _controller.text = label;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
    _emitCustom();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘의 감정 (선택)',
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.inkAlt,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // ── 프리셋 6종 + 직접 입력 칩 ──
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final preset in kEmotionPresets)
              _EmotionChip(
                key: ValueKey('emotion-chip-${preset.code}'),
                label: '${preset.emoji} ${preset.labelKo}',
                selected: _selectedCode == preset.code,
                color: EmotionPalette.accentOf(preset.code),
                onTap: () => _selectPreset(preset.code),
              ),
            _EmotionChip(
              key: const ValueKey('emotion-chip-custom'),
              label: '✏️ 직접 입력',
              selected: _customMode,
              color: EmotionPalette.neutralAccent,
              onTap: _enterCustomMode,
            ),
          ],
        ),
        // ── 직접 입력 필드 + 최근 감정 추천 ──
        if (_customMode) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('emotion-custom-field'),
            controller: _controller,
            maxLength: 20,
            onChanged: _onCustomChanged,
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
            decoration: const InputDecoration(
              hintText: '감정을 자유롭게 적어보세요 (예: 설레는)',
              counterText: '', // 카운터는 아래 별도 표기 대신 maxLength 배지로 충분
              isDense: true,
            ),
          ),
          if (widget.recentLabels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '최근 사용',
              style: textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final label in widget.recentLabels)
                  ActionChip(
                    key: ValueKey('emotion-recent-$label'),
                    label: Text(label),
                    onPressed: () => _pickRecent(label),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// 프리셋/직접입력 공용 선택 칩 — 선택 시 감정 색 테두리+틴트.
class _EmotionChip extends StatelessWidget {
  const _EmotionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.14) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? color : AppColors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.ink,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
