import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Windows: 작업 표시줄 아이콘 등으로 앱을 한 번 더 실행하면 새 프로세스는 바로 끝나고
/// 이미 실행 중인 이 인스턴스에 `activate`를 보낸다(windows/runner/single_instance.cpp).
/// 트레이에 숨어 있었다면 작업 표시줄 숨김을 풀고, 지금 모드(독/창) 그대로 앞으로 가져온다.
class SingleInstance {
  SingleInstance._();

  static const _channel = MethodChannel('art.zoomon.snapdock/instance');

  static void listen() {
    if (!Platform.isWindows) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'activate') return;
      await windowManager.setSkipTaskbar(false);
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
