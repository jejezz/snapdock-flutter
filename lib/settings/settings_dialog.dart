import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'capture_settings.dart';
import 'launch_at_startup.dart';

/// 캡처 설정 창: 녹화 길이와 이미지·영상 저장 위치.
Future<void> showCaptureSettingsDialog(BuildContext context, CaptureSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SettingsDialog(settings: settings),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.settings});

  final CaptureSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.settingsTitle),
      content: SizedBox(
        width: 480,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (settings.launchAtStartup.isSupported) ...[
                _SectionTitle(l10n.settingsGeneralSection),
                _LaunchAtStartupRow(startup: settings.launchAtStartup),
                const SizedBox(height: AppSpacing.xl),
              ],
              _SectionTitle(l10n.settingsRecordingSection),
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
              Text(l10n.settingsGifNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle(l10n.settingsFoldersSection),
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
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonClose))],
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
