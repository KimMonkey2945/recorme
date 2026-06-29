import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// 앱 전역 정적 테마 — "Quiet Journal" 라이트 모드.
///
/// 감정 기반 동적 테마(Phase 4)는 DiaryThemedView에서
/// 이 ThemeData를 베이스로 copyWith 하여 오버라이드한다.
/// 색상·반경·타이포는 AppColors·AppRadius·AppSpacing 토큰을 참조한다.
class AppTheme {
  AppTheme._();

  // ──────────────────────────────────────────
  // 공개 진입점
  // ──────────────────────────────────────────

  /// 라이트 테마 (현재 유일 테마; 다크 모드는 Phase 추후)
  static ThemeData get light => _buildLight();

  // ──────────────────────────────────────────
  // 내부 빌더
  // ──────────────────────────────────────────

  static ThemeData _buildLight() {
    final colorScheme = _colorScheme;
    final textTheme = _textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,

      // ── 스캐폴드 배경: 따뜻한 캔버스 ──
      scaffoldBackgroundColor: AppColors.canvas,

      // ── 앱바 ──
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        // 그림자 없음 — 스크롤 시에도 배경과 일체감 유지
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
        actionsIconTheme: const IconThemeData(color: AppColors.ink),
        // 상태바 아이콘을 어두운 색으로 (밝은 배경 대응)
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // ── 카드 ──
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        // elevation 대신 부드러운 BoxShadow는 위젯 레벨에서 직접 적용;
        // 여기서는 shape만 정의
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
      ),

      // ── Filled 버튼 ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.surface,
          minimumSize: const Size(0, 52),        // 탭 영역 48dp+ 확보
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),

      // ── Outlined 버튼 ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          side: const BorderSide(color: AppColors.accent, width: 1.5),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),

      // ── Text 버튼 ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),

      // ── 인풋 필드 ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.accent,
        ),
      ),

      // ── 구분선 ──
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),

      // ── 하단 내비게이션 바 ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        indicatorColor: AppColors.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.accent, size: 24);
          }
          return const IconThemeData(color: AppColors.inkMuted, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.inkMuted,
          );
        }),
        surfaceTintColor: Colors.transparent,
      ),

      // ── 칩 ──
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.accentSoft,
        labelStyle: textTheme.labelSmall?.copyWith(color: AppColors.accent),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        side: BorderSide.none,
      ),

      // ── 스낵바 ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),

      // ── 다이얼로그 ──
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.ink,
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // ── 바텀시트 ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.modal),
          ),
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // ── 팝업 메뉴 ──
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: AppColors.ink),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  // ──────────────────────────────────────────
  // ColorScheme
  // ──────────────────────────────────────────

  static ColorScheme get _colorScheme => ColorScheme(
        brightness: Brightness.light,
        // 주 강조색 — 더스크 바이올렛
        primary: AppColors.accent,
        onPrimary: AppColors.surface,
        primaryContainer: AppColors.accentSoft,
        onPrimaryContainer: AppColors.accent,
        // 세컨더리 — 보조 텍스트 톤으로 통일
        secondary: AppColors.inkMuted,
        onSecondary: AppColors.surface,
        secondaryContainer: AppColors.hairline,
        onSecondaryContainer: AppColors.ink,
        // 서피스
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        surfaceContainerHighest: AppColors.canvas,
        onSurfaceVariant: AppColors.inkMuted,
        // 아웃라인
        outline: AppColors.hairline,
        outlineVariant: AppColors.hairline,
        // 에러
        error: AppColors.error,
        onError: AppColors.surface,
        errorContainer: AppColors.errorSoft,
        onErrorContainer: AppColors.error,
        // 인버스 — 스낵바 등
        inverseSurface: AppColors.ink,
        onInverseSurface: AppColors.surface,
        inversePrimary: AppColors.accentSoft,
        // 그림자·틴트
        shadow: Color(0x14232228),       // ink 8% 투명도
        scrim: Color(0x80232228),        // ink 50% 투명도
        surfaceTint: Colors.transparent, // 틴트 비활성 — 순수 색상 유지
      );

  // ──────────────────────────────────────────
  // TextTheme
  // ──────────────────────────────────────────

  /// 타이포 스케일: 시스템 폰트(iOS: SF Pro / Android: Roboto) 기반.
  /// google_fonts 미사용 — 한국어 커버리지·analyze 클린 유지.
  static TextTheme get _textTheme => const TextTheme(
        // display 28 / w700 — 주요 헤드라인 (달, 연도 표시 등)
        displayLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          height: 1.3,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          height: 1.3,
          letterSpacing: -0.3,
        ),
        displaySmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          height: 1.3,
        ),

        // title 20 / w600 — 화면 제목, 섹션 헤더
        headlineLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          height: 1.35,
        ),
        headlineMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          height: 1.35,
        ),
        headlineSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          height: 1.4,
        ),

        // titleLarge: AppBar 제목, 다이얼로그 제목
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          height: 1.4,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          height: 1.4,
        ),

        // body 15 / w400 / height 1.5 — 기록 본문·일반 콘텐츠
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
          height: 1.5,          // 넉넉한 행간 — 기록 본문 가독성
          letterSpacing: 0.1,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
          height: 1.5,
          letterSpacing: 0.1,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.inkMuted,
          height: 1.5,
        ),

        // label 13 / w500 — 버튼, 칩, 탭 레이블
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          letterSpacing: 0.1,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
          letterSpacing: 0.2,
        ),
        // caption 12 / w400 (inkMuted) — 날짜, 부제, 메타 정보
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.inkMuted,
          letterSpacing: 0.3,
        ),
      );
}

