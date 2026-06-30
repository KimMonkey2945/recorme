import 'package:flutter/material.dart';

/// 감정(primaryEmotion) 기반 큐레이트 색상 팔레트.
///
/// LLM이 내려주는 backgroundColor/textColor/accentColor는 모델 품질에 의존하므로
/// 여기서 결정론적으로 색을 매핑한다. primaryEmotion 코드를 받아 미리 검증된
/// 파스텔 조합을 반환하며, 미상이거나 null이면 [DiaryTheme.neutral]로 폴백한다.
///
/// ## 재사용
/// - 상세 화면 배경: [DiaryTheme.fromEmotion]으로 배경·텍스트·강조색 적용.
/// - 캘린더 감정색 차별화(013-C): [backgroundColor]를 dot/하이라이트에 활용.
/// - 목록 감정 뱃지 등 후속 기능도 이 팔레트를 단일 진실원으로 참조한다.
///
/// ## 설계 기준
/// - 모든 배경은 밝은 파스텔 → 어두운 [textColor]로 WCAG AA 대비 충족.
/// - [accentColor]는 강조선·이모지 칩·AI코멘트 색조 등 포인트 요소에 사용.
class DiaryTheme {
  const DiaryTheme._({
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
  });

  /// 감정 배경색 (파스텔 계열).
  final Color backgroundColor;

  /// 본문 잉크색 — 배경 위 가독성을 위한 어두운 계열.
  final Color textColor;

  /// 강조색 — 배지·코멘트·구분선 포인트에 사용.
  final Color accentColor;

  // ──────────────────────────────────────────
  // 팩토리
  // ──────────────────────────────────────────

  /// [primaryEmotion] 코드(대소문자 무관)로 해당 팔레트를 반환한다.
  /// 매핑에 없는 코드 또는 null이면 [neutral]로 폴백한다.
  static DiaryTheme fromEmotion(String? primaryEmotion) =>
      _palette[primaryEmotion?.toUpperCase()] ?? neutral;

  // ──────────────────────────────────────────
  // 팔레트 상수
  // ──────────────────────────────────────────

  /// 기쁨 / 행복 — 연노랑 계열
  static const DiaryTheme joy = DiaryTheme._(
    backgroundColor: Color(0xFFFFF3D6),
    textColor: Color(0xFF3A2E12),
    accentColor: Color(0xFFF5A623),
  );

  /// 슬픔 / 우울 — 연파랑 계열
  static const DiaryTheme sadness = DiaryTheme._(
    backgroundColor: Color(0xFFE3EDF7),
    textColor: Color(0xFF1F2A37),
    accentColor: Color(0xFF4A77B5),
  );

  /// 분노 / 짜증 — 연코랄 계열
  static const DiaryTheme anger = DiaryTheme._(
    backgroundColor: Color(0xFFFBE3DE),
    textColor: Color(0xFF3A1A14),
    accentColor: Color(0xFFD64531),
  );

  /// 평온 / 안정 — 연초록 계열
  static const DiaryTheme calm = DiaryTheme._(
    backgroundColor: Color(0xFFE2F1E8),
    textColor: Color(0xFF1C2B22),
    accentColor: Color(0xFF4CA06A),
  );

  /// 불안 / 긴장 — 연보라 계열
  static const DiaryTheme anxiety = DiaryTheme._(
    backgroundColor: Color(0xFFECE6F6),
    textColor: Color(0xFF25203A),
    accentColor: Color(0xFF7A5AC2),
  );

  /// 중립 / 미분류 — 옅은 웜그레이 (폴백)
  static const DiaryTheme neutral = DiaryTheme._(
    backgroundColor: Color(0xFFF2F1ED),
    textColor: Color(0xFF232228),
    accentColor: Color(0xFF6541F2),
  );

  // ──────────────────────────────────────────
  // 내부 룩업 맵
  // ──────────────────────────────────────────

  /// primaryEmotion 코드(대문자) → 팔레트 맵.
  /// 모든 비교는 [fromEmotion]에서 toUpperCase() 후 진행한다.
  static const Map<String, DiaryTheme> _palette = {
    'JOY': joy,
    'HAPPY': joy,       // LLM이 HAPPY를 내려줄 경우를 대비한 별칭
    'SADNESS': sadness,
    'SAD': sadness,
    'ANGER': anger,
    'ANGRY': anger,
    'CALM': calm,
    'PEACEFUL': calm,
    'ANXIETY': anxiety,
    'ANXIOUS': anxiety,
    'NEUTRAL': neutral,
  };
}
