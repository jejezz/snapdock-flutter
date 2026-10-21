import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// 썸네일 크기. 목업의 S 32px, M 44px(기본), L 64px.
enum DockSize {
  small(32),
  medium(44),
  large(64);

  const DockSize(this.width);
  final double width;

  DockSize get next => DockSize.values[(index + 1) % DockSize.values.length];
}

/// 메인 창을 항상 위의 작은 독으로 바꿨다가 되돌린다.
abstract final class DockWindow {
  static const _normalSize = Size(960, 640);
  static const _normalMinimum = Size(960, 600);

  /// 세로는 썸네일 높이에 ✕ 배지가 넘치는 여백을 더한 값이다.
  static Size sizeFor({required int count, required DockSize size}) {
    const visibleMax = 8;
    final shown = count.clamp(0, visibleMax);
    const chrome = 12.0 + 20 + 6 + 28 * 3 + 6; // 안쪽 여백 + 손잡이 + 단추 3개
    final thumbs = shown * (size.width + 6);
    return Size((chrome + thumbs).clamp(180, 900), size.width * 0.75 + 28);
  }

  static Future<void> enter(Size size) async {
    await windowManager.setMinimumSize(const Size(100, 40));
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setSize(size, animate: true);
  }

  static Future<void> resize(Size size) => windowManager.setSize(size, animate: true);

  static Future<void> exit() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(_normalMinimum);
    await windowManager.setSize(_normalSize);
    await windowManager.center();
  }
}
