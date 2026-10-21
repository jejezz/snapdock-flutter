// From jejezz/application-release-templates common/ @ conventions-v1.
//
// Saturn 디자인 언어의 기준 구현 (conventions/ui-ux.md, theming.md, fonts.md).
// daylight-commander → dove-zip으로 이어진 테마를 규약에 맞게 정리했다:
// ColorScheme의 모든 슬롯을 채우고(onSurfaceVariant 등이 Material 기본값으로
// 빠지지 않게), 간격·모서리 토큰과 대체 글꼴을 더했다. 앱 고유 색(파일 종류
// 색 등)은 이 파일이 아니라 앱 쪽에 라이트·다크 한 쌍으로 둔다.

import 'package:flutter/material.dart';

abstract final class AppColors {
  // Dark
  static const bg = Color(0xFF0A0E14);
  static const surface = Color(0xFF151D27);
  static const surfaceHi = Color(0xFF1D2733);
  static const stroke = Color(0x1AFFFFFF);
  static const strokeStrong = Color(0x33FFFFFF);
  static const textHi = Color(0xFFF1F5F9);
  static const textMid = Color(0xFFA9B4C4);
  static const textLow = Color(0xFF6B7787);

  // Light
  static const bgLight = Color(0xFFF4F6FA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceHiLight = Color(0xFFE3E8EF);
  static const strokeLight = Color(0x14000000);
  static const strokeStrongLight = Color(0x24000000);
  static const textHiLight = Color(0xFF101828);
  static const textMidLight = Color(0xFF5B6676);
  static const textLowLight = Color(0xFF8A94A6);

  // Brand
  static const primary = Color(0xFF4C9DFF);
  static const primaryDeep = Color(0xFF2C6BE0);
  static const accent = Color(0xFF7C5CFF);

  // Semantics — 아이콘·점·배경용. 흰 배경 위 글자에는 *Text 변형을 쓴다
  // (warning #FFB020은 흰 바탕에서 대비가 부족하다, theming.md §2).
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF5A5F);
  static const successTextLight = Color(0xFF047857);
  static const warningTextLight = Color(0xFFB45309);
  static const dangerTextLight = Color(0xFFC81E24);
}

abstract final class AppRadius {
  static const sheet = 32.0;
  static const card = 24.0;
  static const tile = 20.0;
  static const button = 10.0;
  static const iconChip = 7.0;
  static const chip = 999.0;
}

/// 4의 배수 간격 (ui-ux.md §3).
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppFonts {
  static const family = 'SeoulNamsan';

  /// SeoulNamsan에 없는 글자를 OS 한글 글꼴로 넘긴다 (fonts.md §2).
  static const fallback = ['Apple SD Gothic Neo', 'Malgun Gothic', 'Noto Sans CJK KR', 'Noto Sans KR'];

  /// 파일 이름·경로 등 앱이 통제하지 않는 문자열 (fonts.md §3).
  static const userContent = TextStyle(fontFamilyFallback: fallback);

  /// 로그, 16진수, 체크섬 (fonts.md §4). 'monospace'는 데스크톱에서 해석되지 않는다.
  static const mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: [
    'SF Mono', 'Consolas', 'Cascadia Mono', 'DejaVu Sans Mono', 'Noto Sans Mono', 'Courier New',
  ]);
}

abstract final class AppTheme {
  static ThemeData dark({bool dense = true}) => _base(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          onSecondary: Colors.white,
          error: AppColors.danger,
          onError: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textHi,
          onSurfaceVariant: AppColors.textMid,
          surfaceContainerHighest: AppColors.surfaceHi,
          surfaceContainerHigh: AppColors.surfaceHi,
          surfaceContainer: AppColors.surface,
          surfaceContainerLow: AppColors.surface,
          surfaceContainerLowest: AppColors.bg,
          outline: AppColors.strokeStrong,
          outlineVariant: AppColors.stroke,
          inverseSurface: AppColors.textHi,
          onInverseSurface: AppColors.bg,
          inversePrimary: AppColors.primaryDeep,
          shadow: Colors.black,
          scrim: Colors.black,
        ),
        background: AppColors.bg,
        textLow: AppColors.textLow,
        dense: dense,
      );

  static ThemeData light({bool dense = true}) => _base(
        const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.primaryDeep,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          onSecondary: Colors.white,
          error: AppColors.dangerTextLight,
          onError: Colors.white,
          surface: AppColors.surfaceLight,
          onSurface: AppColors.textHiLight,
          onSurfaceVariant: AppColors.textMidLight,
          surfaceContainerHighest: AppColors.surfaceHiLight,
          surfaceContainerHigh: AppColors.surfaceHiLight,
          surfaceContainer: AppColors.surfaceLight,
          surfaceContainerLow: AppColors.surfaceLight,
          surfaceContainerLowest: AppColors.bgLight,
          outline: AppColors.strokeStrongLight,
          outlineVariant: AppColors.strokeLight,
          inverseSurface: AppColors.textHiLight,
          onInverseSurface: AppColors.bgLight,
          inversePrimary: AppColors.primary,
          shadow: Colors.black,
          scrim: Colors.black,
        ),
        background: AppColors.bgLight,
        textLow: AppColors.textLowLight,
        dense: dense,
      );

  /// [dense]: 데스크톱 밀도(본문 13)와 모바일 밀도(본문 15), ui-ux.md §4.
  static ThemeData _base(ColorScheme scheme,
      {required Color background, required Color textLow, required bool dense}) {
    final hi = scheme.onSurface;
    final mid = scheme.onSurfaceVariant;
    final body = dense ? 13.0 : 15.0;
    final small = dense ? 11.5 : 13.0;
    const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)));
    final buttonSize = Size(0, dense ? 36 : 44);
    final buttonText = TextStyle(fontFamily: AppFonts.family, fontSize: body, fontWeight: FontWeight.w700);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppFonts.family,
      fontFamilyFallback: AppFonts.fallback,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        headlineMedium: TextStyle(fontSize: dense ? 20 : 34, fontWeight: FontWeight.w800, color: hi),
        titleLarge: TextStyle(fontSize: dense ? 16 : 20, fontWeight: FontWeight.w700, color: hi),
        titleMedium: TextStyle(fontSize: dense ? 14 : 17, fontWeight: FontWeight.w700, color: hi),
        titleSmall: TextStyle(fontSize: body, fontWeight: FontWeight.w700, color: hi),
        bodyLarge: TextStyle(fontSize: body + 1, color: hi),
        bodyMedium: TextStyle(fontSize: body, color: hi),
        bodySmall: TextStyle(fontSize: small, color: mid),
        labelLarge: TextStyle(fontSize: body, fontWeight: FontWeight.w700, color: hi),
        labelMedium: TextStyle(fontSize: small, fontWeight: FontWeight.w500, color: mid),
        labelSmall: TextStyle(fontSize: small - 0.5, color: textLow),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        // 앱 바 높이는 앱마다 따로 정하지 않고 여기서만 정한다 (ui-ux.md §4).
        toolbarHeight: dense ? 44 : kToolbarHeight,
        foregroundColor: hi,
        titleTextStyle: TextStyle(fontFamily: AppFonts.family, fontSize: dense ? 16 : 20, fontWeight: FontWeight.w700, color: hi),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: buttonText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: buttonText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide.none,
        ),
      ),
      // M3 기본값은 팝업이 배경에 묻힌다 — surfaceHi + 테두리 (daylight).
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      // 액션 글자색이 배경과 구분되도록 명시 (dove-zip의 "복사" 버튼 문제).
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(fontFamily: AppFonts.family, fontSize: body, color: hi),
        actionTextColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      focusColor: scheme.primary.withValues(alpha: 0.18),
    );
  }
}
