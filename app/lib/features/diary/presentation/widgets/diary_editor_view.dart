import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:record/core/theme/app_colors.dart';
import 'package:record/core/theme/app_spacing.dart';
import 'package:record/features/diary/presentation/widgets/diary_image_embed_builder.dart';
import 'package:record/features/diary/presentation/widgets/diary_quill_styles.dart';

/// 기록 작성/수정 화면의 순수 표현 위젯(리치 텍스트).
///
/// Scaffold·AppBar·배경 그라데이션은 상위 페이지가 담당하며, 이 위젯은 에디터
/// 콘텐츠 영역(날짜 칩 + 서식 툴바 + 리치 에디터 + 글자수 카운터 + 버튼 바)만 책임진다.
/// [QuillController] 생성·본문 로드·글자수 제한·이미지 업로드/삽입·저장은 모두 상위
/// [DiaryEditorPage]가 담당하고, 여기서는 컨트롤러와 콜백만 받아 표시한다.
///
/// ## 레이아웃
/// ```
/// _DateChip
/// QuillSimpleToolbar     ← 폰트/크기·굵게/기울임/밑줄·목록 + 사진 삽입(custom)
/// Expanded(QuillEditor)  ← 본문(인라인 이미지 포함)
/// _CharCounter           ← 순수 텍스트 기준 글자수(3단계 색상)
/// _BottomButtonBar       ← 취소 + 저장
/// ```
///
/// ## 알려진 한계 (웹 한글 IME)
/// flutter_quill 에디터는 Flutter **웹**에서 한글(CJK) IME 조합 입력이 제대로
/// 동작하지 않는다(영문은 정상). 이는 flutter_quill + Flutter 웹의 알려진 한계로
/// 앱 설정 수준의 확실한 우회가 없다. **한글 입력은 Android/iOS(모바일)에서 정상**이며
/// 모바일 기기/에뮬레이터로 검증한다. (웹은 영문·서식·이미지·날짜 흐름 검증용.)
class DiaryEditorView extends StatelessWidget {
  const DiaryEditorView({
    super.key,
    required this.dateText,
    required this.controller,
    required this.plainLength,
    this.maxLength = 500,
    required this.saving,
    required this.onRegister,
    required this.onRemember,
    required this.onCancel,
    required this.onPickImage,
  });

  /// 표시용 날짜 문자열 (예: '2026년 6월 24일').
  final String dateText;

  /// 본문 리치 텍스트 컨트롤러(상위가 생성·소유).
  final QuillController controller;

  /// 현재 순수 텍스트 길이(상위가 계산해 전달 — 카운터·저장 가능 판단용).
  ///
  /// 매 글자 입력마다 [QuillEditor] 전체가 rebuild되면 한글 IME 조합/입력 연결이
  /// 끊겨 백스페이스가 1회 후 멈추므로, 길이는 [setState]가 아닌 리스너블로 받아
  /// 카운터·버튼만 [ValueListenableBuilder]로 갱신한다(에디터는 rebuild 제외).
  final ValueListenable<int> plainLength;

  /// 본문 최대 글자 수(순수 텍스트 기준 하드 제한). 기본 500자.
  final int maxLength;

  /// 저장 진행 중이면 true — 버튼을 로딩 상태로 전환.
  final bool saving;

  /// '등록' 버튼 탭 콜백 — confirm:false로 임시 저장(DRAFT).
  final VoidCallback onRegister;

  /// '오늘을 기억하기' 버튼 탭 콜백 — 확인 다이얼로그 후 confirm:true로 확정.
  final VoidCallback onRemember;

  /// 취소 버튼 탭 콜백.
  final VoidCallback onCancel;

  /// 사진 삽입 버튼 탭 콜백(상위가 picker→업로드→Delta 삽입 처리).
  final VoidCallback onPickImage;

  /// 카드 반경과 일치하는 상수 BorderRadius.
  static const BorderRadius _kCardRadius =
      BorderRadius.all(Radius.circular(AppRadius.card));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 날짜 읽기 전용 칩 ────────────────────────────────────
          _DateChip(dateText: dateText),
          const SizedBox(height: AppSpacing.md),

          // ── 서식 툴바 (사진 삽입 custom 버튼 포함) ─────────────────
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
            ),
            child: QuillSimpleToolbar(
              controller: controller,
              config: QuillSimpleToolbarConfig(
                // 단일 가로 스크롤 행(여러 줄로 펼치면 작은 화면에서 세로 넘침).
                multiRowsDisplay: false,
                showSearchButton: false,
                showLink: false,
                showCodeBlock: false,
                showInlineCode: false,
                // 사진 삽입: 갤러리 선택 → 업로드 → 커서 위치 임베드(상위 처리).
                customButtons: [
                  QuillToolbarCustomButtonOptions(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    tooltip: '사진 삽입',
                    onPressed: saving ? null : onPickImage,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── 본문 리치 에디터 ─────────────────────────────────────
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                // 종이 질감 — 따뜻한 베이지 배경.
                color: AppColors.paper,
                borderRadius: _kCardRadius,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.hairline),
                ),
              ),
              child: QuillEditor.basic(
                controller: controller,
                config: QuillEditorConfig(
                  placeholder: '오늘 하루를 기록해보세요',
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  expands: true,
                  embedBuilders: const [DiaryImageEmbedBuilder()],
                  // 종이 + 명조(serif) 본문.
                  customStyles: diaryPaperStyles(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // ── 글자수 카운터 + 하단 버튼 바 ─────────────────────────
          // 길이 변화는 이 부분만 rebuild한다(위 에디터는 rebuild 제외 → IME 보존).
          ValueListenableBuilder<int>(
            valueListenable: plainLength,
            builder: (context, length, _) {
              final canSave = length > 0 && !saving;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 글자수 카운터 (순수 텍스트 기준, 우측 정렬)
                  _CharCounter(current: length, max: maxLength),
                  const SizedBox(height: AppSpacing.md),

                  // 하단 버튼 바
                  _BottomButtonBar(
                    saving: saving,
                    canSave: canSave,
                    onRegister: onRegister,
                    onRemember: onRemember,
                    onCancel: onCancel,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 날짜 읽기 전용 칩
// ─────────────────────────────────────────────────────────────────────────────

/// 선택된 날짜를 표시하는 읽기 전용 텍스트.
/// 시안: pill 배지 대신 plain Text(inkAlt 600 14px)로 단순화.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.dateText});

  final String dateText;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        dateText,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.inkAlt,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 글자수 카운터
// ─────────────────────────────────────────────────────────────────────────────

/// 우측 정렬 글자수 카운터(순수 텍스트 기준). 비율에 따라 3단계 색상.
///
/// | 비율 | 색상 | 의미 |
/// |------|------|------|
/// | < 80% | inkMuted | 평상시 |
/// | 80~95% | warning (앰버) | 주의 구간 |
/// | ≥ 95% | error (레드) | 초과 임박 |
class _CharCounter extends StatelessWidget {
  const _CharCounter({required this.current, required this.max});

  final int current;
  final int max;

  /// 이진 색상 — 최대치에 도달했을 때만 error, 그 외는 inkMuted.
  Color _resolveColor() {
    if (current >= max) return AppColors.error;
    return AppColors.inkMuted;
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor();
    final baseStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        style: baseStyle.copyWith(color: color),
        child: Text('$current / $max'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 하단 버튼 바 (취소 + 등록 + 오늘을 기억하기)
// ─────────────────────────────────────────────────────────────────────────────

/// 취소(OutlinedButton) + 등록(OutlinedButton·보조) + 오늘을 기억하기(FilledButton·주) 배치.
///
/// 좁은 화면에서도 세 버튼이 한 줄에 수평 배치되도록 각 버튼의 수평 패딩을 최소화하고,
/// 취소는 고정 너비, 등록과 기억하기는 1:1 Expanded로 남은 공간을 균등 분배한다.
class _BottomButtonBar extends StatelessWidget {
  const _BottomButtonBar({
    required this.saving,
    required this.canSave,
    required this.onRegister,
    required this.onRemember,
    required this.onCancel,
  });

  final bool saving;
  final bool canSave;

  /// '등록' 버튼 탭 콜백.
  final VoidCallback onRegister;

  /// '오늘을 기억하기' 버튼 탭 콜백.
  final VoidCallback onRemember;

  /// '취소' 버튼 탭 콜백.
  final VoidCallback onCancel;

  static const double _kButtonHeight = 52;

  static const OutlinedBorder _kButtonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
  );

  @override
  Widget build(BuildContext context) {
    // 저장 진행 중 로딩 인디케이터(기억하기 버튼 내부).
    const Widget loadingIndicator = SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.surface),
      ),
    );

    return Row(
      children: [
        // ── 취소 버튼 (고정 너비) ────────────────────────────
        SizedBox(
          height: _kButtonHeight,
          child: OutlinedButton(
            onPressed: saving ? null : onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.inkMuted,
              side: const BorderSide(color: AppColors.hairline),
              shape: _kButtonShape,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            child: const Text('취소'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // ── 등록 버튼 (보조, Expanded 1/2) ──────────────────
        Expanded(
          child: SizedBox(
            height: _kButtonHeight,
            child: OutlinedButton(
              onPressed: canSave ? onRegister : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                disabledForegroundColor: AppColors.primarySoft,
                shape: _kButtonShape,
                padding: EdgeInsets.zero,
              ),
              child: const Text('등록'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // ── 오늘을 기억하기 버튼 (주, Expanded 1/2) ──────────
        Expanded(
          child: SizedBox(
            height: _kButtonHeight,
            child: FilledButton(
              onPressed: canSave ? onRemember : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primarySoft,
                shape: _kButtonShape,
                padding: EdgeInsets.zero,
              ),
              // 반짝이 아이콘 + 라벨 (시안: auto_awesome 아이콘 추가)
              child: saving
                  ? loadingIndicator
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 16),
                        SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            '오늘을 기억하기',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
