// From jejezz/application-release-templates common/ @ conventions-v1.
// 설정 저장 키·기존 키 이전·언어 해석 (localization.md §3·§5).
// snapdock를 앱의 pubspec name으로 바꾼다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapdock/settings/app_settings.dart';
import 'package:snapdock/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to system theme and system language', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.system);
    expect(s.locale, isNull);
  });

  test('persists under theme_mode / app_locale', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    await s.setThemeMode(ThemeMode.dark);
    await s.setLocale(const Locale('en'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getString('app_locale'), 'en');
    await s.setLocale(null);
    expect(prefs.containsKey('app_locale'), isFalse);
  });

  test('moves a legacy key once', () async {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final s = await AppSettings.load(legacyKeys: {'locale': AppSettings.localeKey});
    final prefs = await SharedPreferences.getInstance();
    expect(s.locale, const Locale('en'));
    expect(prefs.containsKey('locale'), isFalse);
  });

  test('non-Korean system languages resolve to English', () {
    const supported = [Locale('ko'), Locale('en')];
    expect(AppSettings.resolveLocale(const Locale('ko', 'KR'), supported), const Locale('ko'));
    expect(AppSettings.resolveLocale(const Locale('ja'), supported), const Locale('en'));
    expect(AppSettings.resolveLocale(null, supported), const Locale('en'));
  });

  test('palette and text scale default, persist and ignore bad values', () async {
    SharedPreferences.setMockInitialValues({});
    var s = await AppSettings.load();
    expect(s.palette, ColorPalette.saturn);
    expect(s.textScale, 1.0);
    await s.setPalette(ColorPalette.rose);
    await s.setTextScale(1.15);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_palette'), 'rose');
    expect(prefs.getDouble('text_scale'), 1.15);
    s = await AppSettings.load();
    expect(s.palette, ColorPalette.rose);
    expect(s.textScale, 1.15);

    SharedPreferences.setMockInitialValues({'theme_palette': 'nope', 'text_scale': 3.0});
    s = await AppSettings.load();
    expect(s.palette, ColorPalette.saturn);
    expect(s.textScale, 1.0);
  });

  test('theme primary follows the palette; high contrast is pure black/white', () {
    expect(AppTheme.dark(palette: ColorPalette.teal).colorScheme.primary, const Color(0xFF2DD4BF));
    expect(AppTheme.light(palette: ColorPalette.amber).colorScheme.primary, const Color(0xFFB45309));
    expect(AppTheme.dark(palette: ColorPalette.saturn).colorScheme.primary, AppColors.primary);
    expect(AppTheme.dark(palette: ColorPalette.highContrast).colorScheme.surface, Colors.black);
    expect(AppTheme.light(palette: ColorPalette.highContrast).colorScheme.surface, Colors.white);
    expect(AppTheme.dark(palette: ColorPalette.rose).dividerColor, AppColors.stroke);
  });
}
