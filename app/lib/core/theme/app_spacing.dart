import 'package:flutter/material.dart';

/// 앱 전역 간격(spacing) 토큰.
/// 매직 넘버 대신 이 상수를 사용해 일관된 여백을 유지한다.
class AppSpacing {
  AppSpacing._();

  /// 4dp — 아이콘과 텍스트 사이 등 극소 간격
  static const double xs = 4;

  /// 8dp — 칩 내부 패딩, 작은 항목 간격
  static const double sm = 8;

  /// 12dp — 리스트 항목 내부 세로 패딩
  static const double md = 12;

  /// 16dp — 카드 내부 패딩, 섹션 간격 기본값
  static const double lg = 16;

  /// 24dp — 주요 섹션 간 여백
  static const double xl = 24;

  /// 32dp — 페이지 상단 여백, 대형 섹션 구분
  static const double xxl = 32;

  /// 화면 좌우 기본 수평 패딩
  static const double screenHorizontal = lg;

  /// 화면 상하 기본 수직 패딩
  static const double screenVertical = xl;
}

/// 앱 전역 모서리 반경(border radius) 토큰.
class AppRadius {
  AppRadius._();

  /// 2dp — 거의 직각, 배지 등 소형 요소
  static const double xs = 2;

  /// 8dp — 인풋 필드, 작은 컨테이너
  static const double sm = 8;

  /// 14dp — 버튼 반경
  static const double button = 14;

  /// 16dp — 바텀시트, 모달 상단
  static const double modal = 16;

  /// 20dp — 카드 반경 (Quiet Journal 핵심 형태 토큰)
  static const double card = 20;

  /// 999dp — 완전한 pill 형태 (칩, 뱃지, FAB)
  static const double chip = 999;

  /// ---------- 편의 BorderRadius 헬퍼 ----------

  /// 카드용 BorderRadius
  static BorderRadius get cardBorderRadius =>
      BorderRadius.circular(card);

  /// 버튼용 BorderRadius
  static BorderRadius get buttonBorderRadius =>
      BorderRadius.circular(button);

  /// Pill(칩)용 BorderRadius
  static BorderRadius get chipBorderRadius =>
      BorderRadius.circular(chip);
}
