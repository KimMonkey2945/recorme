import 'package:flutter/material.dart';

/// 감정 표시용 색 팔레트(Task 025 — 감정 연출 축소).
///
/// 감정 기반 **동적 배경/글자 테마·마스코트 연출은 전부 제거**됐다(구 `DiaryTheme`).
/// 감정 색이 남는 곳은 **달력 점 + 감정 칩** 두 곳뿐이며, 여기서는 그 포인트 색(accent)만 정의한다.
/// 프리셋이 아닌 커스텀 감정 라벨이나 미상 코드는 [neutralAccent]로 폴백한다.
class EmotionPalette {
  EmotionPalette._();

  /// 중립/커스텀/미상 폴백 강조색(옅은 보라).
  static const Color neutralAccent = Color(0xFF6541F2);

  /// 프리셋 코드(대문자) → 강조색. 별칭(HAPPY/SAD 등)도 흡수한다.
  static const Map<String, Color> _accent = {
    'JOY': Color(0xFFF5A623),
    'HAPPY': Color(0xFFF5A623),
    'SADNESS': Color(0xFF4A77B5),
    'SAD': Color(0xFF4A77B5),
    'ANGER': Color(0xFFD64531),
    'ANGRY': Color(0xFFD64531),
    'CALM': Color(0xFF4CA06A),
    'PEACEFUL': Color(0xFF4CA06A),
    'ANXIETY': Color(0xFF7A5AC2),
    'ANXIOUS': Color(0xFF7A5AC2),
    'NEUTRAL': neutralAccent,
  };

  /// [emotionCode](대소문자 무관)의 강조색. 프리셋이 아니거나 null이면 [neutralAccent].
  /// 달력 점·감정 칩의 색으로 쓴다(배경 전체를 칠하는 데 쓰지 않는다).
  static Color accentOf(String? emotionCode) =>
      _accent[emotionCode?.toUpperCase()] ?? neutralAccent;

  /// 감정 정보가 조금이라도 있으면(프리셋 코드 또는 커스텀 라벨) 표시할 칩 색.
  /// 커스텀 라벨만 있는 경우 프리셋 색이 없으므로 [neutralAccent]를 쓴다.
  static Color chipColor({String? code, String? label}) {
    if (code != null && code.isNotEmpty) return accentOf(code);
    return neutralAccent; // 커스텀 라벨 전용
  }
}
