import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// 캐릭터 대사 말풍선 — 리액션 오버레이에서 캐릭터가 건네는 한 줄을 담는다.
///
/// 아래쪽(캐릭터 방향)으로 작은 꼬리가 달린 둥근 카드다. 대사는 **맥락 기반**(감정 아님)이며
/// 캐릭터 성격에 따라 말투가 다르다(원숭이 느긋 / 레서판다 애쓰는) — 문구 자체는 서버가 준다.
class CharacterSpeechBubble extends StatelessWidget {
  const CharacterSpeechBubble({super.key, required this.text});

  /// 표시할 대사 한 줄(항상 비어 있지 않게 호출부가 보장한다 — 빈손 리액션 금지).
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hairline),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 아래를 향한 삼각형 꼬리(캐릭터 쪽).
        CustomPaint(
          size: const Size(20, 10),
          painter: _BubbleTailPainter(),
        ),
      ],
    );
  }
}

/// 말풍선 하단 꼬리(아래로 뾰족한 삼각형). 채움색은 말풍선 카드와 동일한 [AppColors.surface].
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
