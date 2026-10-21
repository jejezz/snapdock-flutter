import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../capture/capture_controller.dart';
import '../capture/capture_service.dart';
import 'demo_hooks.dart';

/// 디버그 빌드 전용: README 데모를 스스로 재생한다 (tool/readme/demo.sh가 켠다).
///
/// 마우스나 키보드 입력 없이 독이 하는 일을 차례로 보여 준다: 새 캡처가 들어오고, 썸네일 크기를 바꾸고,
/// 알약으로 접었다 펼친다. 화면에 나오는 캡처는 모두 샘플 그림이다.
///
/// 환경 변수: `SNAPDOCK_DEMO=1`, `SNAPDOCK_DEMO_RECT=x,y,w,h`(녹화 영역, 화면 좌표),
/// `SNAPDOCK_DEMO_SAMPLES`(새로 들어올 PNG 폴더), `SNAPDOCK_DEMO_SIGNAL`(신호 파일을 둘 폴더).
Future<void> runDemoIfRequested(CaptureService service, CaptureController captures) async {
  if (!kDebugMode) return;
  final env = Platform.environment;
  if (env['SNAPDOCK_DEMO'] != '1') return;

  final parts = (env['SNAPDOCK_DEMO_RECT'] ?? '').split(',').map(double.parse).toList();
  final rect = Rect.fromLTWH(parts[0], parts[1], parts[2], parts[3]);
  final samples = Directory(env['SNAPDOCK_DEMO_SAMPLES']!)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.png'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final signal = Directory(env['SNAPDOCK_DEMO_SIGNAL']!);

  Future<void> pause(double seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

  await pause(2); // 독이 자리를 잡을 때까지
  await service.demoBackdrop(rect);
  await pause(1);
  File('${signal.path}/ready').writeAsStringSync('');

  await pause(1.5);
  for (final file in samples) {
    final isCircle = file.path.contains('circle');
    captures.addDemoImage(
      file.readAsBytesSync(),
      width: 1280,
      height: 800,
      shape: isCircle ? CaptureShape.circle : CaptureShape.rect,
    );
    await pause(1.3);
  }
  await pause(0.6);

  for (final hold in [1.6, 1.6, 1.4]) {
    DemoHooks.cycleDockSize?.call();
    await pause(hold);
  }
  DemoHooks.toggleCollapsed?.call();
  await pause(1.8);
  DemoHooks.toggleCollapsed?.call();
  await pause(1.6);

  File('${signal.path}/done').writeAsStringSync('');
  // 녹화가 끝날 때까지 배경을 그대로 둔다. 뒤에 있는 화면이 녹화에 들어가면 안 된다.
  await pause(4);
  await service.demoBackdrop(null);
  exit(0);
}
