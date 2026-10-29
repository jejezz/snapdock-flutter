// From jejezz/application-release-templates common/.
// 고대비 색 구성 (settings.md). snapdock를 앱의 pubspec name으로 바꾼다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapdock/theme/app_theme.dart';

void main() {
  test('고대비는 다크에서 순흑 배경·순백 글자·노란 주색이다', () {
    final s = AppTheme.dark(palette: AccentPalette.highContrast).colorScheme;
    expect(s.surface, Colors.black);
    expect(s.onSurface, Colors.white);
    expect(s.outline, Colors.white);
    expect(s.primary, AccentPalette.highContrast.darkPrimary);
  });

  test('고대비는 라이트에서 순백 배경·순흑 글자·파란 주색이다', () {
    final s = AppTheme.light(palette: AccentPalette.highContrast).colorScheme;
    expect(s.surface, Colors.white);
    expect(s.onSurface, Colors.black);
    expect(s.outline, Colors.black);
    expect(s.primary, AccentPalette.highContrast.lightPrimary);
  });

  test('고대비가 아닌 색 구성은 배경을 바꾸지 않는다', () {
    final base = AppTheme.dark().colorScheme.surface;
    expect(AppTheme.dark(palette: AccentPalette.teal).colorScheme.surface, base);
    expect(AppTheme.dark(palette: AccentPalette.highContrast).colorScheme.surface, isNot(base));
  });
}
