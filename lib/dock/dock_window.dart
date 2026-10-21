import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';

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

  /// 독 아래 설명 한 줄의 높이.
  static const hintHeight = 16.0;

  /// 세로는 썸네일 높이에 ✕ 배지가 넘치는 여백을 더한 값이다.
  static Size sizeFor({required int count, required DockSize size, bool collapsed = false}) {
    if (collapsed) return const Size(132, 40);
    const visibleMax = 8;
    final shown = count.clamp(0, visibleMax);
    const chrome = 12.0 + 20 + 6 + 28 * 6 + 6; // 안쪽 여백 + 손잡이 + 단추 6개
    final thumbs = shown * (size.width + 6);
    return Size(
      (chrome + thumbs).clamp(180, 900),
      size.width * 0.75 + 28 + hintHeight,
    );
  }

  /// 독 창과 화면 위쪽 사이의 간격.
  static const topMargin = 12.0;

  static Future<void> enter(Size size) async {
    await windowManager.setMinimumSize(const Size(100, 40));
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setSize(size);
    await windowManager.setPosition(await _topCenter(size));
  }

  /// 커서가 있는 모니터의 위쪽 가운데. 메뉴 막대나 Dock을 뺀 영역 기준이다.
  static Future<Offset> _topCenter(Size size) async {
    final cursor = await screenRetriever.getCursorScreenPoint();
    final displays = await screenRetriever.getAllDisplays();
    Display? target;
    for (final d in displays) {
      final origin = d.visiblePosition ?? Offset.zero;
      final area = d.visibleSize ?? d.size;
      // 커서가 메뉴 막대 위에 있어도 그 모니터로 본다.
      final rect = Rect.fromLTWH(origin.dx, origin.dy - 60, area.width, area.height + 120);
      if (rect.contains(cursor)) {
        target = d;
        break;
      }
    }
    target ??= await screenRetriever.getPrimaryDisplay();
    final origin = target.visiblePosition ?? Offset.zero;
    final area = target.visibleSize ?? target.size;
    return Offset(origin.dx + (area.width - size.width) / 2, origin.dy + topMargin);
  }

  /// 썸네일이 늘고 줄 때 가로 가운데를 지킨다. 사용자가 독을 다른 곳으로 옮겼어도 그 자리에서 양옆으로 자란다.
  static Future<void> resize(Size size) async {
    final position = await windowManager.getPosition();
    final current = await windowManager.getSize();
    final next = Offset(
      position.dx + (current.width - size.width) / 2,
      position.dy,
    );
    await windowManager.setBounds(null, position: next, size: size);
  }

  static Future<void> exit() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(_normalMinimum);
    await windowManager.setSize(_normalSize);
    await windowManager.center();
  }
}
