import 'package:flutter/material.dart';

/// 앱 전역 테마. (감정 기반 동적 테마는 Phase 4에서 DiaryThemedView로 별도 적용.)
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B8DEF)),
        useMaterial3: true,
      );
}
