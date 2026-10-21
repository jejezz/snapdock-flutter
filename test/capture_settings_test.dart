import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snapdock/capture/capture_service.dart';
import 'package:snapdock/settings/capture_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sent = <Map<Object?, Object?>>[];

  setUp(() {
    sent.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('art.zoomon.snapdock/capture'),
      (call) async {
        if (call.method == 'configure') sent.add(call.arguments as Map<Object?, Object?>);
        return null;
      },
    );
  });

  test('starts with 10 seconds and default folders, and tells the native side', () async {
    final settings = await CaptureSettings.load(CaptureService());
    expect(settings.maxSeconds, 10);
    expect(settings.imageDir, isNull);
    expect(settings.videoDir, isNull);
    expect(sent.single, {'maxSeconds': 10, 'imageDir': null, 'videoDir': null});
  });

  test('keeps the length within limits and persists it', () async {
    final settings = await CaptureSettings.load(CaptureService());
    await settings.setMaxSeconds(500);
    expect(settings.maxSeconds, CaptureSettings.maxSecondsLimit);
    await settings.setMaxSeconds(1);
    expect(settings.maxSeconds, CaptureSettings.minSeconds);
    await settings.setMaxSeconds(25);

    final reloaded = await CaptureSettings.load(CaptureService());
    expect(reloaded.maxSeconds, 25);
    expect(sent.last['maxSeconds'], 25);
  });

  test('saves folders and resets them to the default with null', () async {
    final settings = await CaptureSettings.load(CaptureService());
    await settings.setImageDir('/tmp/shots');
    await settings.setVideoDir('/tmp/clips');
    expect((await CaptureSettings.load(CaptureService())).imageDir, '/tmp/shots');
    expect((await CaptureSettings.load(CaptureService())).videoDir, '/tmp/clips');
    expect(sent.last, {'maxSeconds': 10, 'imageDir': '/tmp/shots', 'videoDir': '/tmp/clips'});

    await settings.setImageDir(null);
    expect((await CaptureSettings.load(CaptureService())).imageDir, isNull);
  });

  test('remembers dock mode and thumbnail size', () async {
    final settings = await CaptureSettings.load(CaptureService());
    expect(settings.dockMode, isFalse);
    expect(settings.dockSizeIndex, 1);

    await settings.setDockMode(true);
    await settings.setDockSizeIndex(2);

    final reloaded = await CaptureSettings.load(CaptureService());
    expect(reloaded.dockMode, isTrue);
    expect(reloaded.dockSizeIndex, 2);
  });

  test('a platform without native capture does not break loading', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('art.zoomon.snapdock/capture'),
      null,
    );
    final settings = await CaptureSettings.load(CaptureService());
    expect(settings.maxSeconds, 10);
  });
}
