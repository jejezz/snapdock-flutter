import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:screen_retriever/screen_retriever.dart';

import 'package:window_manager/window_manager.dart';

import '../window/window_placement.dart';

/// 썸네일 크기. 목업의 S 32px, M 44px(기본), L 64px.
enum DockSize {
  small(32),
  medium(44),
  large(64);

  const DockSize(this.width);
  final double width;

  DockSize get next => DockSize.values[(index + 1) % DockSize.values.length];
}

/// 주 모니터에서 창을 놓는 자리.
enum DockAnchor { topCenter, topRight, center, centerRight }

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

  static const _channel = MethodChannel('art.zoomon.snapdock/capture');

  static Future<void> enter(Size size, {DockAnchor anchor = DockAnchor.topCenter}) async {
    await windowManager.setMinimumSize(const Size(100, 40));
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    // Windows는 제목 표시줄을 숨겨도 창틀(두꺼운 테두리)이 남아 안쪽 폭이 약 16px 줄어든다.
    // 완전히 테두리 없는 창으로 만들어야 요청한 크기가 그대로 안쪽 크기가 된다. exit에서 normal로 되돌린다.
    if (Platform.isWindows) {
      await windowManager.setAsFrameless();
      // 프레임이 없으면 Windows 11 기본 둥근 모서리가 사라지므로 DWM에 다시 지정한다.
      await _channel.invokeMethod('setRoundedCorners', {'rounded': true});
    }
    lastAnchor = anchor;
    await _placeOnPrimary(size, anchor);
  }

  /// 마지막으로 독을 놓은 자리. 다시 펼칠 때 창이 어디서 나타날지 정한다.
  static DockAnchor lastAnchor = DockAnchor.topCenter;

  /// 주 모니터 작업 영역(작업 표시줄·메뉴 막대 제외)의 [anchor] 자리에 논리 크기 [size]인 창을 놓는다.
  /// Windows는 모니터마다 배율이 달라도 어긋나지 않게 물리 픽셀로 계산한다(`window_placement.dart` 참고).
  static Future<void> _placeOnPrimary(Size size, DockAnchor anchor) async {
    final primary = await screenRetriever.getPrimaryDisplay();
    final DisplayArea area;
    if (Platform.isWindows) {
      area = DisplayArea.fromDisplay(primary, primary: true);
    } else {
      final pos = primary.visiblePosition ?? Offset.zero;
      final vis = primary.visibleSize ?? primary.size;
      area = DisplayArea(workArea: pos & vis, scale: 1, primary: true);
    }
    final work = area.workArea;
    final s = area.scale;
    final w = size.width * s, h = size.height * s;
    final margin = topMargin * s;
    final left = switch (anchor) {
      DockAnchor.topCenter || DockAnchor.center => work.left + (work.width - w) / 2,
      DockAnchor.topRight || DockAnchor.centerRight => work.right - w - margin,
    };
    final top = switch (anchor) {
      DockAnchor.topCenter || DockAnchor.topRight => work.top + margin,
      DockAnchor.center || DockAnchor.centerRight => work.top + (work.height - h) / 2,
    };

    var dpr = Platform.isWindows ? windowManager.getDevicePixelRatio() : 1.0;
    if (Platform.isWindows && (dpr - s).abs() >= 0.01) {
      // 창이 다른 배율의 모니터에 있으면 먼저 주 모니터 안으로 옮겨 배율이 바뀌길 기다린다.
      await windowManager.setPosition(Offset((work.left + 40) / dpr, (work.top + 40) / dpr));
      for (var i = 0; i < 12; i++) {
        if ((windowManager.getDevicePixelRatio() - s).abs() < 0.01) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      dpr = windowManager.getDevicePixelRatio();
    }
    await windowManager.setBounds(Rect.fromLTWH(left / dpr, top / dpr, w / dpr, h / dpr));
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
    if (Platform.isWindows) {
      await _channel.invokeMethod('setRoundedCorners', {'rounded': true});
    }
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
    // 최소 크기를 먼저 올리면 작은 독 창이 왼쪽 위 기준으로 960px까지 늘어나 오른쪽으로 쏠린다.
    // 그래서 크기와 위치를 먼저 정하고 최소 크기는 마지막에 건다.
    await _placeOnPrimary(_normalSize, DockAnchor.center);
    await windowManager.setMinimumSize(_normalMinimum);
  }
}
