import 'dart:io';

import '../capture/capture_service.dart';

/// 로그인할 때 앱을 자동으로 시작할지. Windows는 HKCU Run 키, macOS는 로그인 항목(SMAppService).
class LaunchAtStartup {
  LaunchAtStartup(this._service);

  final CaptureService _service;

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  /// 로그인으로 시작할 때 붙는 인자. 트레이 숨김이 켜져 있으면 창 없이 시작한다.
  static const hiddenFlag = '--hidden';

  static const _valueName = 'Snapdock';

  bool get isSupported => Platform.isWindows || Platform.isMacOS;

  Future<bool> isEnabled() async {
    if (Platform.isMacOS) return _service.launchAtLoginEnabled();
    if (!Platform.isWindows) return false;
    final result = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
    return result.exitCode == 0;
  }

  /// 바꾼 뒤의 실제 상태를 돌려준다. 실패하면 예외를 던진다.
  Future<bool> setEnabled(bool enabled) async {
    if (Platform.isMacOS) return _service.setLaunchAtLogin(enabled);
    if (!Platform.isWindows) return false;
    final args = enabled
        ? ['add', _runKey, '/v', _valueName, '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}" $hiddenFlag', '/f']
        : ['delete', _runKey, '/v', _valueName, '/f'];
    final result = await Process.run('reg', args);
    if (result.exitCode != 0 && (enabled || await isEnabled())) {
      throw ProcessException('reg', args, '${result.stderr}', result.exitCode);
    }
    return enabled;
  }
}
