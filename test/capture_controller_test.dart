import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapdock/capture/capture_controller.dart';
import 'package:snapdock/capture/capture_service.dart';

class _FakeService extends CaptureService {
  _FakeService(this.results);

  final List<CaptureResult?> results;
  final copied = <Uint8List>[];
  final copiedFiles = <String>[];

  @override
  Future<CaptureResult?> captureRegion({required CaptureShape shape}) async => results.removeAt(0);

  @override
  Future<void> copyImage(Uint8List png) async => copied.add(png);

  @override
  Future<void> copyFile(String path) async => copiedFiles.add(path);

  @override
  Future<bool> hasPermission() async => true;
}

CaptureResult _image([int byte = 1]) => CaptureResult(
      action: CaptureAction.copy,
      shape: CaptureShape.rect,
      png: Uint8List.fromList([byte, 2, 3]),
      width: 30,
      height: 20,
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('snapdock_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a capture is written to the store and listed newest first', () async {
    final controller = CaptureController(_FakeService([_image(1), _image(2)]), storeDir: dir);
    await controller.capture();
    await controller.capture();

    expect(controller.items.length, 2);
    expect(controller.items.first.id, 2);
    expect(File(controller.items.first.path).readAsBytesSync().first, 2);
    expect(controller.items.first.previewPath, controller.items.first.path);
  });

  test('items survive a restart', () async {
    final first = CaptureController(_FakeService([_image()]), storeDir: dir);
    await first.capture();
    await first.flush();

    final second = CaptureController(_FakeService([_image(9)]), storeDir: dir);
    await second.load();
    expect(second.items.length, 1);
    expect(second.items.single.width, 30);

    await second.capture();
    expect(second.items.first.id, 2, reason: 'ids keep counting after a restart');
  });

  test('items whose files are gone are dropped on load', () async {
    final first = CaptureController(_FakeService([_image()]), storeDir: dir);
    await first.capture();
    await first.flush();
    File(first.items.single.path).deleteSync();

    final second = CaptureController(_FakeService([]), storeDir: dir);
    await second.load();
    expect(second.items, isEmpty);
  });

  test('the oldest items are discarded beyond the limit', () async {
    final controller = CaptureController(
      _FakeService([for (var i = 0; i < CaptureController.maxItems + 3; i++) _image()]),
      storeDir: dir,
    );
    for (var i = 0; i < CaptureController.maxItems + 3; i++) {
      await controller.capture();
    }
    expect(controller.items.length, CaptureController.maxItems);
    expect(controller.items.last.id, 4);
  });

  test('copying an image sends its bytes; a recording sends its file', () async {
    final service = _FakeService([
      _image(5),
      CaptureResult(
        action: CaptureAction.copy,
        shape: CaptureShape.rect,
        kind: CaptureKind.video,
        png: Uint8List.fromList([7]),
        width: 10,
        height: 10,
        durationMs: 3000,
        savedPath: '${Directory.systemTemp.path}/does-not-matter.mp4',
      ),
    ]);
    final controller = CaptureController(service, storeDir: dir);
    await controller.capture();
    await controller.capture();

    await controller.copy(controller.items.last);
    expect(service.copied.single.first, 5);
    await controller.copy(controller.items.first);
    expect(service.copiedFiles.single, endsWith('does-not-matter.mp4'));
    expect(controller.items.first.duration, const Duration(seconds: 3));
  });

  test('removing an item takes it out of the saved list', () async {
    final first = CaptureController(_FakeService([_image(), _image()]), storeDir: dir);
    await first.capture();
    await first.capture();
    first.remove(first.items.first);
    await first.flush();

    final second = CaptureController(_FakeService([]), storeDir: dir);
    await second.load();
    expect(second.items.length, 1);
  });
}
