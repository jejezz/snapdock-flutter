import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_settings.dart';
import 'capture_settings.dart';
import 'launch_at_startup.dart';

/// 캡처 설정 창: 녹화 길이와 이미지·영상 저장 위치.
Future<void> showCaptureSettingsDialog(BuildContext context, CaptureSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SettingsDialog(settings: settings),
  );
}

enum _Section { display, language, general, shortcuts, recording, folders, metadata }

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.settings});

  final CaptureSettings settings;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  _Section _selected = _Section.display;

  CaptureSettings get settings => widget.settings;

  List<_Section> get _sections => [
        _Section.display,
        _Section.language,
        if (settings.launchAtStartup.isSupported) _Section.general,
        _Section.shortcuts,
        _Section.recording,
        _Section.folders,
        if (Platform.isMacOS) _Section.metadata,
      ];

  String _title(AppLocalizations l10n, _Section section) => switch (section) {
        _Section.display => l10n.settingsSectionDisplay,
        _Section.language => l10n.settingsSectionLanguage,
        _Section.general => l10n.settingsGeneralSection,
        _Section.shortcuts => l10n.settingsShortcutsSection,
        _Section.recording => l10n.settingsRecordingSection,
        _Section.folders => l10n.settingsFoldersSection,
        _Section.metadata => l10n.settingsMetadataSection,
      };

  IconData _icon(_Section section) => switch (section) {
        _Section.display => Icons.palette_outlined,
        _Section.language => Icons.language_rounded,
        _Section.general => Icons.tune_rounded,
        _Section.shortcuts => Icons.keyboard_outlined,
        _Section.recording => Icons.videocam_outlined,
        _Section.folders => Icons.folder_outlined,
        _Section.metadata => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sections = _sections;
    // 설정 창은 앱 창보다 커질 수 없다 — 도킹한 좁은 창에서도 들어가도록 창 크기로 정한다 (settings.md).
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(640.0, screen.width - 32);
    final height = (screen.height - 32 - 150).clamp(160.0, 380.0);
    final wide = width >= 560;

    final content = SingleChildScrollView(
      child: ListenableBuilder(
        listenable: Listenable.merge([settings, AppSettingsScope.of(context)]),
        builder: (context, _) => _body(context, l10n, theme, _selected),
      ),
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(l10n.settingsTitle),
      content: SizedBox(
        width: width,
        height: height,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: ListView(
                      children: [
                        for (final section in sections)
                          _SectionTile(
                            title: _title(l10n, section),
                            selected: section == _selected,
                            onTap: () => setState(() => _selected = section),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: AppSpacing.xl),
                  Expanded(child: content),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final section in sections)
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.sm),
                            child: ChoiceChip(
                              showCheckmark: false,
                              avatar: Icon(_icon(section), size: 18),
                              label: Text(_title(l10n, section)),
                              selected: section == _selected,
                              onSelected: (_) => setState(() => _selected = section),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: AppSpacing.xl),
                  Expanded(child: content),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonClose))],
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, ThemeData theme, _Section section) {
    final mac = Platform.isMacOS;
    final note = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final app = AppSettingsScope.of(context);
    return switch (section) {
      _Section.display => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(l10n.settingsBrightness),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded), label: Text(l10n.themeSystem)),
                ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded), label: Text(l10n.themeLight)),
                ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded), label: Text(l10n.themeDark)),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) => app.setThemeMode(s.single),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionTitle(l10n.settingsPalette),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final palette in ColorPalette.values)
                  ChoiceChip(
                    selected: app.palette == palette,
                    onSelected: (_) => app.setPalette(palette),
                    avatar: palette == ColorPalette.highContrast
                        ? const Icon(Icons.contrast_rounded, size: 18)
                        : CircleAvatar(backgroundColor: palette.primaryFor(theme.brightness)),
                    label: Text(_paletteLabel(l10n, palette)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionTitle(l10n.settingsFontSize),
            SegmentedButton<double>(
              segments: [
                ButtonSegment(value: AppSettings.textScales[0], label: Text(l10n.fontScaleSmall)),
                ButtonSegment(value: AppSettings.textScales[1], label: Text(l10n.fontScaleNormal)),
                ButtonSegment(value: AppSettings.textScales[2], label: Text(l10n.fontScaleLarge)),
              ],
              selected: {app.textScale},
              onSelectionChanged: (s) => app.setTextScale(s.single),
            ),
          ],
        ),
      _Section.language => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(l10n.settingsLanguage),
            // 언어 이름은 그 언어로 쓴다 — 잘못 골라도 읽고 되돌아올 수 있게.
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: '', label: Text(l10n.languageSystemShort)),
                const ButtonSegment(value: 'ko', label: Text('한국어')),
                const ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {app.locale?.languageCode ?? ''},
              onSelectionChanged: (s) => app.setLocale(s.single.isEmpty ? null : Locale(s.single)),
            ),
          ],
        ),
      _Section.general => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LaunchAtStartupRow(startup: settings.launchAtStartup),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsHideInTray),
              subtitle: Text(l10n.settingsHideInTrayNote),
              value: settings.hideInTray,
              onChanged: settings.setHideInTray,
            ),
          ],
        ),
      _Section.shortcuts => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShortcutRow(label: l10n.settingsShortcutCapture, keys: mac ? '⌥⇧S' : 'Alt+Shift+S'),
            _ShortcutRow(label: l10n.settingsShortcutDock, keys: mac ? '⌥⇧D' : 'Alt+Shift+D'),
            Text(l10n.settingsShortcutDockNote, style: note),
          ],
        ),
      _Section.recording => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.settingsRecordingLength)),
                Text(l10n.settingsSecondsValue(settings.maxSeconds), style: theme.textTheme.titleSmall),
              ],
            ),
            Slider(
              min: CaptureSettings.minSeconds.toDouble(),
              max: CaptureSettings.maxSecondsLimit.toDouble(),
              divisions: CaptureSettings.maxSecondsLimit - CaptureSettings.minSeconds,
              value: settings.maxSeconds.toDouble(),
              label: l10n.settingsSecondsValue(settings.maxSeconds),
              onChanged: (v) => settings.setMaxSeconds(v.round()),
            ),
            Text(l10n.settingsGifNote, style: note),
          ],
        ),
      _Section.folders => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FolderRow(
              label: l10n.settingsImageFolder,
              path: settings.imageDir,
              defaultLabel: l10n.settingsImageFolderDefault,
              onChanged: settings.setImageDir,
            ),
            const SizedBox(height: AppSpacing.md),
            _FolderRow(
              label: l10n.settingsVideoFolder,
              path: settings.videoDir,
              defaultLabel: l10n.settingsVideoFolderDefault,
              onChanged: settings.setVideoDir,
            ),
          ],
        ),
      _Section.metadata => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsEmbedMetadata),
          subtitle: Text(l10n.settingsEmbedMetadataNote),
          value: settings.embedMetadata,
          onChanged: settings.setEmbedMetadata,
        ),
    };
  }

  String _paletteLabel(AppLocalizations l10n, ColorPalette palette) => switch (palette) {
        ColorPalette.saturn => l10n.settingsPaletteSaturn,
        ColorPalette.teal => l10n.settingsPaletteTeal,
        ColorPalette.amber => l10n.settingsPaletteAmber,
        ColorPalette.rose => l10n.settingsPaletteRose,
        ColorPalette.slate => l10n.settingsPaletteSlate,
        ColorPalette.highContrast => l10n.settingsPaletteHighContrast,
      };
}

/// 선택한 구역은 배경 대신 왼쪽 굵은 선으로 표시한다 (고대비에서 글자와 겹치지 않게).
/// 선택 안 된 줄도 같은 폭을 비워 글자가 밀리지 않는다.
class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.title, required this.selected, required this.onTap});

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(width: 3, height: 36, color: selected ? theme.colorScheme.primary : Colors.transparent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(title, style: selected ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _LaunchAtStartupRow extends StatefulWidget {
  const _LaunchAtStartupRow({required this.startup});

  final LaunchAtStartup startup;

  @override
  State<_LaunchAtStartupRow> createState() => _LaunchAtStartupRowState();
}

class _LaunchAtStartupRowState extends State<_LaunchAtStartupRow> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    widget.startup.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    }, onError: (_) {
      if (mounted) setState(() => _enabled = false);
    });
  }

  Future<void> _toggle(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsLaunchAtStartupFailed;
    setState(() => _enabled = value);
    try {
      final actual = await widget.startup.setEnabled(value);
      if (mounted) setState(() => _enabled = actual);
    } catch (_) {
      if (!mounted) return;
      setState(() => _enabled = !value);
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(AppLocalizations.of(context).settingsLaunchAtStartup),
      value: _enabled ?? false,
      onChanged: _enabled == null ? null : _toggle,
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(keys, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.label, required this.path, required this.defaultLabel, required this.onChanged});

  final String label;
  final String? path;
  final String defaultLabel;
  final Future<void> Function(String?) onChanged;

  Future<void> _choose() async {
    final dir = await getDirectoryPath(initialDirectory: path);
    if (dir != null) await onChanged(dir);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                path ?? defaultLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (path != null) TextButton(onPressed: () => onChanged(null), child: Text(l10n.settingsResetFolder)),
            OutlinedButton(onPressed: _choose, child: Text(l10n.settingsChooseFolder)),
          ],
        ),
      ],
    );
  }
}
