import 'package:flutter/material.dart';

/// 앱 전역 컬러 토큰 — "Quiet Journal" 디자인 컨셉.
///
/// 감정 기반 동적 테마(Phase 4)는 별도 테마 객체로 주입되므로,
/// 여기서는 중립 캔버스 역할의 6가지 고정 토큰만 정의한다.
class AppColors {
  AppColors._();

  // ──────────────────────────────────────────
  // 배경 / 서피스
  // ──────────────────────────────────────────

  /// 앱 배경 — 따뜻한 페이퍼 화이트 (#F7F5F0)
  static const Color canvas = Color(0xFFF7F5F0);

  /// 카드·시트 배경 — 순수 화이트 (#FFFFFF)
  static const Color surface = Color(0xFFFFFFFF);

  /// 화사한 웜 배경 그라데이션 (Foodu 톤 참고) — 상단 피치 → 하단 라이트.
  /// 로그인·캘린더 등 주요 화면의 공용 배경.
  static const Color bgGradientTop = Color(0xFFFFE9D6);
  static const Color bgGradientBottom = Color(0xFFFFFBF6);
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgGradientTop, bgGradientBottom],
  );

  // ──────────────────────────────────────────
  // 텍스트
  // ──────────────────────────────────────────

  /// 본문 텍스트 — 웜 니어블랙 (#232228)
  static const Color ink = Color(0xFF232228);

  /// 보조 텍스트 — 뮤트 퍼플그레이 (#9B98A3)
  static const Color inkMuted = Color(0xFF9B98A3);

  // ──────────────────────────────────────────
  // 강조색
  // ──────────────────────────────────────────

  /// 주 강조색 — 차분한 더스크 바이올렛 (#6C5CE0)
  static const Color accent = Color(0xFF6C5CE0);

  /// 강조 틴트 — 오늘 하이라이트·칩 배경 (#ECE9FB)
  static const Color accentSoft = Color(0xFFECE9FB);

  // ──────────────────────────────────────────
  // 구분선
  // ──────────────────────────────────────────

  /// 헤어라인 구분선 — 따뜻한 오프화이트 (#ECE8E1)
  static const Color hairline = Color(0xFFECE8E1);

  // ──────────────────────────────────────────
  // 시맨틱 (에러/경고/성공 등)
  // ──────────────────────────────────────────

  /// 에러 / 파괴적 액션 강조색
  static const Color error = Color(0xFFD94F4F);

  /// 에러 틴트 배경
  static const Color errorSoft = Color(0xFFFCECEC);

  /// 경고색 — 글자수 80~95% 구간·주의 강조 (웜 앰버 #E09B2D)
  static const Color warning = Color(0xFFE09B2D);

  /// 경고 틴트 배경 — 경고 메시지 배경 등
  static const Color warningSoft = Color(0xFFFAF0DC);
}
