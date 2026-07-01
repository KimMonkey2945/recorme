import 'package:flutter/material.dart';

/// 앱 전역 컬러 토큰 — Wanted Design System 기반.
///
/// ## 색 역할 분리 (중요)
/// - [primary] 계열(블루): 주 CTA·링크·선택·입력 포커스·FAB 등 "조작" 맥락.
/// - [accent] 계열(바이올렛): 감정 분석·AI 코멘트·sparkle 등 "감정/AI" 맥락.
///   → 두 색을 혼용하지 말 것. 버튼은 [primary], 감정·분석 표현은 [accent].
/// - 감정 기반 동적 테마(상세 화면)는 [DiaryTheme]가 별도 주입한다.
class AppColors {
  AppColors._();

  // ──────────────────────────────────────────
  // 배경 / 서피스
  // ──────────────────────────────────────────

  /// 앱 배경 — 순수 화이트 (#FFFFFF).
  static const Color canvas = Color(0xFFFFFFFF);

  /// 카드·시트 배경 — 순수 화이트 (#FFFFFF)
  static const Color surface = Color(0xFFFFFFFF);

  /// 보조 배경 — 밝은 쿨그레이 (#F7F7F8). 섹션 구분·비활성 영역.
  static const Color bgAlt = Color(0xFFF7F7F8);

  /// 종이 배경 — 따뜻한 베이지 (#FBF9F4). 에디터·상세 화면 베이스.
  static const Color paper = Color(0xFFFBF9F4);

  /// 기본 배경 그라데이션 — 흰색 (로그인·캘린더 공용 캔버스).
  static const Color bgGradientTop = Color(0xFFFFFFFF);
  static const Color bgGradientBottom = Color(0xFFFFFFFF);
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgGradientTop, bgGradientBottom],
  );

  // ──────────────────────────────────────────
  // 텍스트 (쿨 뉴트럴 스케일)
  // ──────────────────────────────────────────

  /// 본문/제목 텍스트 — 니어블랙 (#171717)
  static const Color ink = Color(0xFF171717);

  /// 보조 텍스트 — 쿨그레이 (#7C8089). 부제·메타 정보.
  static const Color inkAlt = Color(0xFF7C8089);

  /// 약한 보조 텍스트 — 옅은 쿨그레이 (#98989E). 플레이스홀더·비활성 라벨.
  static const Color inkMuted = Color(0xFF98989E);

  // ──────────────────────────────────────────
  // Primary (블루) — 주 CTA·링크·선택·포커스
  // ──────────────────────────────────────────

  /// 주색 — Wanted 블루 (#3366FF). 버튼·링크·선택·FAB·입력 포커스.
  static const Color primary = Color(0xFF3366FF);

  /// 주색 강조 — 진한 블루 (#005EEB). hover·pressed 등.
  static const Color primaryStrong = Color(0xFF005EEB);

  /// 주색 틴트 — 옅은 블루 배경 (#EAF0FF). 선택 하이라이트·indicator.
  static const Color primarySoft = Color(0xFFEAF0FF);

  // ──────────────────────────────────────────
  // Accent (바이올렛) — 감정 / AI 강조
  // ──────────────────────────────────────────

  /// 강조색 — 바이올렛 (#6541F2). 감정 분석·AI 코멘트·sparkle 등 AI 맥락 전용.
  static const Color accent = Color(0xFF6541F2);

  /// 강조 틴트 — 옅은 바이올렛 배경 (#F0ECFE). 분석중 카드·무드 칩 배경.
  static const Color accentSoft = Color(0xFFF0ECFE);

  // ──────────────────────────────────────────
  // 구분선
  // ──────────────────────────────────────────

  /// 헤어라인 구분선 — 쿨그레이 (#E0E1E6)
  static const Color hairline = Color(0xFFE0E1E6);

  // ──────────────────────────────────────────
  // 시맨틱 (에러/경고)
  // ──────────────────────────────────────────

  /// 에러 / 파괴적 액션 강조색 (#FF4242)
  static const Color error = Color(0xFFFF4242);

  /// 에러 틴트 배경
  static const Color errorSoft = Color(0xFFFCECEC);

  /// 성공 / 완료 강조색 (#1AC472) — 작심삼일 완료·성공 상태.
  static const Color success = Color(0xFF1AC472);

  /// 성공 틴트 배경 (#E8FAF2) — 완료 배지·성공 카드 배경.
  static const Color successSoft = Color(0xFFE8FAF2);

  /// 경고색 — 글자수 80~95% 구간·주의 강조 (#FF9200)
  static const Color warning = Color(0xFFFF9200);

  /// 경고 틴트 배경 — 경고 메시지 배경 등
  static const Color warningSoft = Color(0xFFFAF0DC);
}
