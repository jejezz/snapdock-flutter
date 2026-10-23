// From jejezz/application-release-templates common/ @ conventions-v1.
//
// 새 앱의 시작점. 규약이 요구하는 연결을 한곳에 모았다:
//   창 크기(window_manager) · 추가 라이선스 · 설정 로드 · 라이트/다크 ·
//   언어 해석 · macOS 앱 메뉴 About · 앱 바 [테마 | 언어 | 정보] · 빈 상태.
// 기존 앱에는 통째로 덮어쓰지 말고 필요한 부분만 옮긴다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'about/about_dialog.dart';
import 'about/app_menu_bar.dart';
import 'about/extra_licenses.dart';
import 'app_identity.dart';
import 'capture/capture_controller.dart';
import 'capture/capture_service.dart';
import 'dock/capture_thumb.dart';
import 'dev/demo_hooks.dart';
import 'dev/demo_runner.dart';
import 'dock/dock_view.dart';
import 'dock/dock_window.dart';
import 'l10n/app_localizations.dart';
import 'settings/app_settings.dart';
import 'settings/capture_settings.dart';
import 'settings/settings_dialog.dart';
import 'settings/settings_menus.dart';
import 'theme/app_theme.dart';
import 'update/update_scope.dart';
import 'update/update_service.dart';
import 'window/focus_tint.dart';

final bool _isDesktop =
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerExtraLicenses();

  final captureService = CaptureService();
  // 캡처한 파일과 목록(index.json)을 두는 곳. 앱을 다시 켜도 독이 그대로 돌아온다.
  final support = await getApplicationSupportDirectory();
  final storeDir = Directory('${support.path}${Platform.pathSeparator}captures');
  final captureSettings = await CaptureSettings.load(captureService, workDir: storeDir.path);
  final captures = CaptureController(captureService, storeDir: storeDir);
  await captures.load();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await hotKeyManager.unregisterAll();
    // ui-ux.md §5: 최소 크기는 960×600 이하 (1366×768 노트북).
    const options = WindowOptions(
      size: Size(960, 640),
      minimumSize: Size(960, 600),
      center: true,
      title: AppIdentity.displayName,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      // 마지막에 독으로 끝냈다면 독으로 시작한다 (커서가 있는 모니터의 위쪽 가운데).
      if (captureSettings.dockMode) {
        final size = DockSize.values[captureSettings.dockSizeIndex.clamp(0, DockSize.values.length - 1)];
        await DockWindow.enter(DockWindow.sizeFor(count: captures.items.length, size: size, collapsed: captureSettings.dockCollapsed));
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final settings = await AppSettings.load();
  // 데스크톱이 아니거나 UPDATE_SERVER 가 비어 있으면 null — 업데이트 확인 없음.
  final updates = await UpdateService.create();
  // UpdateScope 는 MaterialApp 위에 둔다 — 정보 창이 이것을 읽어 "업데이트 확인" 단추를 붙인다.
  unawaited(runDemoIfRequested(captureService, captures));
  runApp(
    UpdateScope(
      service: updates,
      child: App(settings: settings, updates: updates, captures: captures, captureSettings: captureSettings),
    ),
  );
}

class App extends StatefulWidget {
  const App({super.key, required this.settings, this.updates, required this.captures, required this.captureSettings});

  final AppSettings settings;
  final CaptureController captures;
  final CaptureSettings captureSettings;
  final UpdateService? updates;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  CaptureController get _captures => widget.captures;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_syncWindowBrightness);
    _syncWindowBrightness();
    widget.updates?.startAutomaticCheck(_navigatorKey);
    if (_isDesktop) _registerCaptureHotkey();
  }

  /// 전역 단축키 ⌥⇧S. 다른 앱을 쓰는 중에도 캡처를 시작한다.
  Future<void> _registerCaptureHotkey() async {
    final hotKey = HotKey(
      key: PhysicalKeyboardKey.keyS,
      modifiers: [HotKeyModifier.alt, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => _captures.capture(),
    );
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncWindowBrightness);
    WidgetsBinding.instance.removeObserver(this);
    _captures.dispose();
    super.dispose();
  }

  // 앱에서 다크를 골라도 OS가 라이트면 제목 표시줄은 밝게 남는다 (theming.md §4).
  @override
  void didChangePlatformBrightness() => _syncWindowBrightness();

  void _syncWindowBrightness() {
    if (!_isDesktop || Platform.isLinux) return;
    final brightness = switch (widget.settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    windowManager.setBrightness(brightness);
  }

  void _showAbout() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);
    showAppAboutDialog(
      context,
      tagline: l10n.aboutTagline,
      description: l10n.aboutDescription,
      onCheckForUpdates: widget.updates == null
          ? null
          : () => widget.updates!.checkManually(context),
    );
  }

  void _checkForUpdates() {
    final context = _navigatorKey.currentContext;
    if (context != null) widget.updates?.checkManually(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: widget.settings,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          title: AppIdentity.displayName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(dense: _isDesktop),
          darkTheme: AppTheme.dark(dense: _isDesktop),
          themeMode: widget.settings.themeMode,
          locale: widget.settings.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: AppSettings.resolveLocale,
          builder: (context, child) => AppMenuBar(
            onAbout: _showAbout,
            onCheckForUpdates: widget.updates == null ? null : _checkForUpdates,
            child: child!,
          ),
          home: HomeScreen(onAbout: _showAbout, captures: _captures, captureSettings: widget.captureSettings),
        ),
      ),
    );
  }
}

/// 홈 화면. 캡처 목록을 보여 주고, 독 모드로 줄일 수 있다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onAbout, required this.captures, required this.captureSettings});

  final VoidCallback onAbout;
  final CaptureController captures;
  final CaptureSettings captureSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late bool _dock = widget.captureSettings.dockMode;
  late bool _collapsed = widget.captureSettings.dockCollapsed;
  late DockSize _dockSize = DockSize.values[widget.captureSettings.dockSizeIndex.clamp(0, DockSize.values.length - 1)];
  int _lastCount = 0;

  CaptureController get _captures => widget.captures;

  @override
  void initState() {
    super.initState();
    _lastCount = _captures.items.length;
    _captures.addListener(_onCapturesChanged);
    if (kDebugMode) {
      DemoHooks.cycleDockSize = _cycleDockSize;
      DemoHooks.toggleCollapsed = _toggleCollapsed;
    }
    if (_isDesktop) _captures.refreshPermission();
  }

  @override
  void dispose() {
    _captures.removeListener(_onCapturesChanged);
    DemoHooks.cycleDockSize = null;
    DemoHooks.toggleCollapsed = null;
    super.dispose();
  }

  void _onCapturesChanged() {
    final count = _captures.items.length;
    if (_dock && !_collapsed && count != _lastCount) {
      DockWindow.resize(DockWindow.sizeFor(count: count, size: _dockSize));
    }
    _lastCount = count;
  }

  Future<void> _enterDock() async {
    setState(() => _dock = true);
    widget.captureSettings.setDockMode(true);
    await DockWindow.enter(
      DockWindow.sizeFor(count: _captures.items.length, size: _dockSize, collapsed: _collapsed),
    );
  }

  Future<void> _exitDock() async {
    setState(() => _dock = false);
    widget.captureSettings.setDockMode(false);
    await DockWindow.exit();
  }

  /// 독을 알약으로 접거나 다시 펼친다.
  void _toggleCollapsed() {
    setState(() => _collapsed = !_collapsed);
    widget.captureSettings.setDockCollapsed(_collapsed);
    DockWindow.resize(
      DockWindow.sizeFor(count: _captures.items.length, size: _dockSize, collapsed: _collapsed),
    );
  }

  void _cycleDockSize() {
    setState(() => _dockSize = _dockSize.next);
    widget.captureSettings.setDockSizeIndex(_dockSize.index);
    DockWindow.resize(
      DockWindow.sizeFor(count: _captures.items.length, size: _dockSize, collapsed: _collapsed),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dock) {
      return DockView(
        controller: _captures,
        size: _dockSize,
        onSizeChanged: _cycleDockSize,
        onExpand: _exitDock,
        collapsed: _collapsed,
        onToggleCollapsed: _toggleCollapsed,
      );
    }
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const FocusTint(),
        title: const Text(AppIdentity.displayName),
        actions: [
          PopupMenuButton<SaveFolder>(
            tooltip: l10n.openFolderTooltip,
            icon: const Icon(Icons.folder_open_rounded),
            onSelected: _captures.openSaveFolder,
            itemBuilder: (_) => [
              PopupMenuItem(value: SaveFolder.pictures, child: Text(l10n.openPicturesFolder)),
              PopupMenuItem(value: SaveFolder.movies, child: Text(l10n.openMoviesFolder)),
            ],
          ),
          IconButton(
            tooltip: l10n.dockShrinkTooltip,
            icon: const Icon(Icons.close_fullscreen_rounded),
            onPressed: _enterDock,
          ),
          IconButton(
            tooltip: l10n.settingsTooltip,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showCaptureSettingsDialog(context, widget.captureSettings),
          ),
          const ThemeMenuButton(),
          const LanguageMenuButton(),
          IconButton(
            tooltip: l10n.aboutTooltip,
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: widget.onAbout,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: ListenableBuilder(
        listenable: _captures,
        builder: (context, _) => Column(
          children: [
            if (_captures.permissionDenied)
              _PermissionBanner(controller: _captures),
            Expanded(
              child: _captures.items.isEmpty
                  ? _EmptyState(controller: _captures)
                  : _CaptureGrid(controller: _captures),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.capturePermissionTitle,
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    l10n.capturePermissionBody,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: controller.openPermissionSettings,
              child: Text(l10n.capturePermissionOpen),
            ),
          ],
        ),
      ),
    );
  }
}

/// 모양(사각형/원형)을 고르고 캡처를 시작하는 줄. 목록이 비어 있어도 있어도 같은 모양이다.
class _CaptureBar extends StatelessWidget {
  const _CaptureBar({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<CaptureShape>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: CaptureShape.rect,
              icon: const Icon(Icons.crop_square_rounded),
              tooltip: l10n.shapeRect,
            ),
            ButtonSegment(
              value: CaptureShape.circle,
              icon: const Icon(Icons.circle_outlined),
              tooltip: l10n.shapeCircle,
            ),
            ButtonSegment(
              value: CaptureShape.window,
              icon: const Icon(Icons.web_asset_rounded),
              tooltip: l10n.shapeWindow,
            ),
          ],
          selected: {
            controller.shape == CaptureShape.screen
                ? CaptureShape.rect
                : controller.shape,
          },
          onSelectionChanged: (s) => controller.setShape(s.first),
        ),
        const SizedBox(width: AppSpacing.md),
        FilledButton(
          onPressed: controller.busy ? null : controller.capture,
          child: Text(l10n.homeEmptyAction),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          l10n.captureHotkeyHint(captureShortcutLabel),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(AppIdentity.iconAsset, width: 48, height: 48),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.homeEmptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          _CaptureBar(controller: controller),
        ],
      ),
    );
  }
}

/// 목록을 비우기 전에 한 번 묻는다. 지워지는 것은 독의 항목뿐이고 사용자 폴더에 저장한 파일은 그대로다.
Future<void> _confirmClearAll(BuildContext context, CaptureController controller) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.clearAllTitle),
      content: Text(l10n.clearAllBody),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.clearAllConfirm),
        ),
      ],
    ),
  );
  if (confirmed == true) controller.clear();
}

class _CaptureGrid extends StatelessWidget {
  const _CaptureGrid({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              _CaptureBar(controller: controller),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _confirmClearAll(context, controller),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(AppLocalizations.of(context).clearAllButton),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final item in controller.items)
                    CaptureEntrance(
                      key: ValueKey(item.id),
                      item: item,
                      child: CaptureThumb(
                        controller: controller,
                        item: item,
                        width: 180,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
