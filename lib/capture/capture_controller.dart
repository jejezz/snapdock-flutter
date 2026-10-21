import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'capture_service.dart';

/// 캡처 목록과 현재 모드를 들고 있다. 독과 홈 화면이 같은 것을 본다.
class CaptureController extends ChangeNotifier {
  CaptureController(this._service);

  final CaptureService _service;

  final List<CaptureItem> _items = [];
  CaptureShape _shape = CaptureShape.rect;
  bool _busy = false;
  bool _permissionDenied = false;
  int _nextId = 1;

  /// 최신 캡처가 앞에 온다.
  List<CaptureItem> get items => List.unmodifiable(_items);
  CaptureShape get shape => _shape;
  bool get busy => _busy;
  bool get permissionDenied => _permissionDenied;

  void setShape(CaptureShape shape) {
    if (_shape == shape) return;
    _shape = shape;
    notifyListeners();
  }

  Future<void> refreshPermission() async {
    final ok = await _service.hasPermission();
    if (_permissionDenied == !ok) return;
    _permissionDenied = !ok;
    notifyListeners();
  }

  Future<void> requestPermission() async {
    await _service.requestPermission();
    await refreshPermission();
  }

  Future<void> openPermissionSettings() => _service.openPermissionSettings();

  /// 단축키나 단추에서 부른다. 이미 선택 중이면 무시한다.
  Future<void> capture() async {
    if (_busy) {
      // 녹화 중에 단축키를 한 번 더 누르면 일찍 끝낸다. 선택 중이면 네이티브가 무시한다.
      await _service.stopRecording();
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await _service.captureRegion(shape: _shape);
      if (_permissionDenied) _permissionDenied = false;
      if (result == null) return;
      // 화면 전체는 일회성 동작이라 다음 모드로 기억하지 않는다.
      if (result.shape != CaptureShape.screen) _shape = result.shape;
      _items.insert(
        0,
        CaptureItem(
          id: _nextId++,
          png: result.png,
          width: result.width,
          height: result.height,
          shape: result.shape,
          createdAt: DateTime.now(),
          kind: result.kind,
          filePath: result.kind == CaptureKind.image ? null : result.savedPath,
          duration: result.durationMs == null
              ? null
              : Duration(milliseconds: result.durationMs!),
          savedPath: result.kind == CaptureKind.image ? result.savedPath : null,
        ),
      );
    } on CapturePermissionDenied {
      _permissionDenied = true;
      // 처음이면 시스템 권한 창이 뜬다. 이미 거부했다면 아무 일도 없으니 배너가 설정으로 안내한다.
      await _service.requestPermission();
    } on MissingPluginException {
      // 이 플랫폼의 네이티브 캡처가 아직 없다 (Windows 구현 전).
      debugPrint(
        'Snapdock: native capture is not available on this platform yet',
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> copy(CaptureItem item) {
    final path = item.filePath;
    return path == null
        ? _service.copyImage(item.png)
        : _service.copyFile(path);
  }

  /// 사용자 폴더(사진/동영상)로 저장하고 그 경로를 돌려준다.
  Future<String?> save(CaptureItem item) {
    final path = item.filePath;
    return path == null
        ? _service.saveImage(item.png)
        : _service.saveFile(path);
  }

  void remove(CaptureItem item) {
    if (_items.remove(item)) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}
