import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 3일 스텝의 시각 상태. 상세 화면이 체크 상태 + 오늘 날짜로부터 계산해 넘긴다.
///
/// - [done]: 완료 체크됨 (success)
/// - [today]: 오늘 차례(아직 미완료) (primary)
/// - [missed]: 놓친 날 (error)
/// - [future]: 아직 오지 않은 날 (hairline)
enum ResolutionStepState { done, today, missed, future }

/// 3일 도전 진행을 노드 3개 + 커넥터로 표현하는 스텝 행.
///
/// 각 노드는 1·2·3일차를 뜻하며, 상태색은 accent(감정 전용) 없이
/// success/primary/error/hairline만 사용한다.
class ResolutionStepRow extends StatelessWidget {
  const ResolutionStepRow({super.key, required this.states});

  /// day_index 순(1·2·3일차) 스텝 상태. 항상 3개.
  final List<ResolutionStepState> states;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(states.length * 2 - 1, (i) {
        // 짝수 index=노드, 홀수 index=커넥터.
        if (i.isOdd) {
          // 커넥터 색: 앞 노드가 done이면 success, 아니면 hairline.
          final prev = states[(i - 1) ~/ 2];
          return Expanded(
            child: Container(
              height: 3,
              color: prev == ResolutionStepState.done
                  ? AppColors.success
                  : AppColors.hairline,
            ),
          );
        }
        final stepIndex = i ~/ 2;
        return _StepNode(dayNumber: stepIndex + 1, state: states[stepIndex]);
      }),
    );
  }
}

/// 스텝 노드 하나(원 + 일차 라벨). 상태별 채움/테두리/아이콘을 달리한다.
class _StepNode extends StatelessWidget {
  const _StepNode({required this.dayNumber, required this.state});

  final int dayNumber;
  final ResolutionStepState state;

  @override
  Widget build(BuildContext context) {
    final (Color color, bool filled, IconData? icon) = switch (state) {
      ResolutionStepState.done => (AppColors.success, true, Icons.check),
      ResolutionStepState.today => (AppColors.primary, true, null),
      ResolutionStepState.missed => (AppColors.error, true, Icons.close),
      ResolutionStepState.future => (AppColors.hairline, false, null),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: filled ? color : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: 20, color: AppColors.surface)
              : Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    // 채워진 today는 흰 글자, 비워진 future는 회색 글자.
                    color: filled ? AppColors.surface : AppColors.inkMuted,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          '$dayNumber일차',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.inkAlt,
          ),
        ),
      ],
    );
  }
}
