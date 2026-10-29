// From jejezz/application-release-templates common/ @ conventions-v2.
//
// 테마·언어·색 구성 전환 UI (conventions/settings-screen.md, theming.md §3,
// localization.md §4). 모두 설정 화면 "외형" 구역 안에만 둔다 — 앱 바에는
// 테마/언어 아이콘 대신 설정 아이콘 하나(⌘,/Ctrl+,)만 둔다.
//   ModeSegmentedButton / AccentPaletteChips / LanguageSegmentedButton:
//     데스크톱·모바일 공통, 설정 화면 "외형" 구역에 이 순서로 넣는다.
//   ThemeMenuButton / LanguageMenuButton: conventions-v1의 앱 바 팝업 메뉴.
//     새 앱에는 쓰지 않는다 — 기존 앱이 옮겨 갈 때까지만 남겨 둔다.

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_settings.dart';

/// 언어 이름은 그 언어로 쓴다 — 잘못 골라도 읽고 되돌아올 수 있게.
const _languages = [(Locale('ko'), '한국어'), (Locale('en'), 'English')];

IconData _themeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };

String _themeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };

class ThemeMenuButton extends StatelessWidget {
  const ThemeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<ThemeMode>(
      tooltip: l10n.themeMenuTooltip,
      icon: Icon(_themeIcon(settings.themeMode)),
      initialValue: settings.themeMode,
      onSelected: settings.setThemeMode,
      itemBuilder: (_) => [
        for (final mode in ThemeMode.values)
          CheckedPopupMenuItem(
            value: mode,
            checked: mode == settings.themeMode,
            child: Text(_themeLabel(l10n, mode)),
          ),
      ],
    );
  }
}

class LanguageMenuButton extends StatelessWidget {
  const LanguageMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    // PopupMenuButton can't carry null as a value, so '' stands for "system".
    final current = settings.locale?.languageCode ?? '';
    return PopupMenuButton<String>(
      tooltip: l10n.languageMenuTooltip,
      icon: const Icon(Icons.language_rounded),
      initialValue: current,
      onSelected: (code) => settings.setLocale(code.isEmpty ? null : Locale(code)),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: '', checked: current.isEmpty, child: Text(l10n.languageSystem)),
        const PopupMenuDivider(),
        for (final (locale, name) in _languages)
          CheckedPopupMenuItem(
            value: locale.languageCode,
            checked: current == locale.languageCode,
            child: Text(name),
          ),
      ],
    );
  }
}

/// 모바일 설정 화면용.
class ThemeSegmentedButton extends StatelessWidget {
  const ThemeSegmentedButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<ThemeMode>(
      segments: [
        for (final mode in ThemeMode.values)
          ButtonSegment(value: mode, icon: Icon(_themeIcon(mode)), label: Text(_themeLabel(l10n, mode))),
      ],
      selected: {settings.themeMode},
      onSelectionChanged: (s) => settings.setThemeMode(s.single),
    );
  }
}

/// 설정 화면 "외형" 구역의 모드(시스템/라이트/다크) 단추 (settings-screen.md §3).
class ModeSegmentedButton extends StatelessWidget {
  const ModeSegmentedButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(_themeIcon(ThemeMode.system), size: 16),
          label: Text(l10n.settingsModeSystem),
        ),
        ButtonSegment(value: ThemeMode.light, icon: Icon(_themeIcon(ThemeMode.light), size: 16), label: Text(l10n.themeLight)),
        ButtonSegment(value: ThemeMode.dark, icon: Icon(_themeIcon(ThemeMode.dark), size: 16), label: Text(l10n.themeDark)),
      ],
      selected: {settings.themeMode},
      onSelectionChanged: (s) => settings.setThemeMode(s.first),
    );
  }
}

/// 설정 화면 "외형" 구역의 색 구성 선택 (settings-screen.md §4). 고대비는 색 원 대신
/// 아이콘(contrast)으로 구분한다 — 주색 하나가 아니라 전체 대비를 바꾸는 항목이라서다.
class AccentPaletteChips extends StatelessWidget {
  const AccentPaletteChips({super.key});

  static String _label(AppLocalizations l10n, AccentPalette p) => switch (p) {
        AccentPalette.saturn => l10n.settingsPaletteSaturn,
        AccentPalette.teal => l10n.settingsPaletteTeal,
        AccentPalette.amber => l10n.settingsPaletteAmber,
        AccentPalette.rose => l10n.settingsPaletteRose,
        AccentPalette.slate => l10n.settingsPaletteSlate,
        AccentPalette.highContrast => l10n.settingsPaletteHighContrast,
      };

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in AccentPalette.values)
          ChoiceChip(
            selected: settings.accentPalette == p,
            showCheckmark: false,
            avatar: p == AccentPalette.highContrast
                ? Icon(Icons.contrast_rounded, size: 14, color: Theme.of(context).colorScheme.onSurface)
                : Icon(Icons.circle, size: 14, color: p.primaryFor(brightness)),
            label: Text(_label(l10n, p)),
            onSelected: (_) => settings.setAccentPalette(p),
          ),
      ],
    );
  }
}

/// 모바일 설정 화면용.
class LanguageSegmentedButton extends StatelessWidget {
  const LanguageSegmentedButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(value: '', label: Text(l10n.languageSystemShort)),
        for (final (locale, name) in _languages) ButtonSegment(value: locale.languageCode, label: Text(name)),
      ],
      selected: {settings.locale?.languageCode ?? ''},
      onSelectionChanged: (s) => settings.setLocale(s.single.isEmpty ? null : Locale(s.single)),
    );
  }
}
