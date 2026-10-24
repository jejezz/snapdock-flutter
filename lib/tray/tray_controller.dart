import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../settings/capture_settings.dart';

/// 트레이 메뉴에 붙는 글자. 언어가 바뀌면 [TrayController.labels]를 갈아 끼운다.
class TrayLabels {
  const TrayLabels({
    required this.tooltip,
    required this.openWindow,
    required this.openDock,
    required this.capture,
    required this.hide,
    required this.quit,
  });

  final String tooltip;
  final String openWindow;
  final String openDock;
  final String capture;
  final String hide;
  final String quit;
}

/// 창을 독 모양이나 일반 창으로 바꾸는 일은 화면(HomeScreen)이 하고, 여기서는 부르기만 한다.
class WindowModeHooks {
  static Future<void> Function()? showAsDock;
  static Future<void> Function()? showAsWindow;

  /// 지금 독 모드인가.
  static bool Function()? isDock;
}

/// 트레이 아이콘, 닫을 때 숨기기, 숨은 상태에서의 독 전환을 맡는다.
class TrayController with TrayListener, WindowListener {
  TrayController({required this.settings, required this.labels, required this.onCapture});

  final CaptureSettings settings;
  final void Function() onCapture;
  TrayLabels labels;

  bool _active = false;

  static bool get isSupported => Platform.isWindows || Platform.isMacOS;

  /// 설정에 맞게 트레이 아이콘과 닫기 가로채기를 켜거나 끈다.
  Future<void> sync() async {
    if (!isSupported) return;
    final want = settings.hideInTray;
    if (want && !_active) {
      _active = true;
      trayManager.addListener(this);
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      if (Platform.isWindows) {
        await trayManager.setIcon('assets/icon/tray_icon.ico');
      } else {
        // 단색 템플릿 이미지: 메뉴바의 라이트/다크에 맞춰 macOS가 색을 입힌다.
        await trayManager.setIcon('assets/icon/tray_icon_mac.png', isTemplate: true);
      }
    } else if (!want && _active) {
      _active = false;
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      return;
    }
    if (_active) await trayManager.setToolTip(labels.tooltip);
  }

  Future<void> hideWindow() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> openAsDock() async {
    await WindowModeHooks.showAsDock?.call();
    await showWindow();
  }

  Future<void> openAsWindow() async {
    await WindowModeHooks.showAsWindow?.call();
    await showWindow();
  }

  /// 단축키용: 숨어 있으면 독으로 꺼내고, 보이면 독과 창을 번갈아 바꾼다.
  Future<void> toggleDock() async {
    if (!await windowManager.isVisible()) return openAsDock();
    if (WindowModeHooks.isDock?.call() ?? false) return openAsWindow();
    return openAsDock();
  }

  @override
  void onWindowClose() => hideWindow();

  @override
  void onTrayIconMouseDown() async {
    if (await windowManager.isVisible()) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.setContextMenu(
      Menu(items: [
        MenuItem(key: 'window', label: labels.openWindow),
        MenuItem(key: 'dock', label: labels.openDock),
        MenuItem(key: 'capture', label: labels.capture),
        MenuItem(key: 'hide', label: labels.hide),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: labels.quit),
      ]),
    );
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'window':
        await openAsWindow();
      case 'dock':
        await openAsDock();
      case 'capture':
        onCapture();
      case 'hide':
        await hideWindow();
      case 'quit':
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
    }
  }
}
