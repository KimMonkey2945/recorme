import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 공감 버튼 크기 프리셋(피드 카드=compact, 상세=large).
enum ReactionButtonSize { compact, large }

/// 공감(하트) 버튼. [reacted]/[count]는 부모가 주입한 값을 그대로 렌더한다(로직 없음).
/// 낙관적 갱신·서버 호출은 [onTap] 호출부(provider)가 담당한다.
/// 공감이 켜지는 순간(false→true) 하트가 살짝 튀는 바운스 애니메이션을 준다.
class ReactionButton extends StatefulWidget {
  const ReactionButton({
    super.key,
    required this.reacted,
    required this.count,
    this.onTap,
    this.accentColor,
    this.size = ReactionButtonSize.compact,
  });

  final bool reacted;
  final int count;

  /// null이면 비활성(비대화형 표시).
  final VoidCallback? onTap;

  /// 강조색. 카드에서는 감정 accentColor를 주입한다. 기본 [AppColors.accent].
  final Color? accentColor;

  final ReactionButtonSize size;

  @override
  State<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<ReactionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.35)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_controller);
  }

  @override
  void didUpdateWidget(covariant ReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 공감이 새로 켜진 순간에만 바운스.
    if (!oldWidget.reacted && widget.reacted) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? AppColors.accent;
    final large = widget.size == ReactionButtonSize.large;
    final iconSize = large ? 26.0 : 18.0;
    final fontSize = large ? 15.0 : 13.0;
    final color = widget.reacted ? accent : AppColors.inkMuted;

    return Semantics(
      button: true,
      label: widget.reacted ? '공감 취소' : '공감하기',
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Icon(
                  widget.reacted ? Icons.favorite : Icons.favorite_border,
                  size: iconSize,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  '${widget.count}',
                  key: ValueKey<int>(widget.count),
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: color,
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
