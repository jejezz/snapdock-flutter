import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'capture_service.dart';

/// 캡처 목록과 현재 모드를 들고 있다. 독과 홈 화면이 같은 것을 본다.
///
/// 항목의 내용은 [storeDir]에 파일로 두고 목록은 `index.json`에 적어서,
/// 앱을 다시 켜도 독이 그대로 돌아온다.
class CaptureController extends ChangeNotifier {
  CaptureController(this._service, {required this.storeDir});

  /// 보관하는 최대 개수. 넘치면 오래된 것부터 지운다.
  static const maxItems = 30;

  /// 지운 항목의 파일을 바로 지우지 않고 기다리는 시간. 다른 앱이 방금 끌어간 파일을 복사 중일 수 있다.
  static const deleteDelay = Duration(seconds: 15);

  final CaptureService _service;
  final Directory storeDir;

  final List<CaptureItem> _items = [];
  CaptureShape _shape = CaptureShape.rect;
  bool _busy = false;
  bool _permissionDenied = false;
  int _nextId = 1;
  Future<void> _writing = Future.value();

  /// 최신 캡처가 앞에 온다.
  List<CaptureItem> get items => List.unmodifiable(_items);
  CaptureShape get shape => _shape;
  bool get busy => _busy;
  bool get permissionDenied => _permissionDenied;

  File get _indexFile => File('${storeDir.path}${Platform.pathSeparator}index.json');

  /// 저장해 둔 목록을 읽는다. 파일이 사라진 항목은 건너뛴다.
  Future<void> load() async {
    try {
      if (!await _indexFile.exists()) return;
      final json = jsonDecode(await _indexFile.readAsString()) as Map<String, Object?>;
      _nextId = json['nextId'] as int? ?? 1;
      final loaded = <CaptureItem>[];
      for (final raw in (json['items'] as List<Object?>? ?? const [])) {
        try {
          final item = CaptureItem.fromJson((raw! as Map).cast<String, Object?>());
          if (File(item.path).existsSync() && File(item.previewPath).existsSync()) loaded.add(item);
        } catch (_) {
          // 깨진 항목은 건너뛴다.
        }
      }
      _items
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    } catch (e) {
      debugPrint('Snapdock: could not read the capture index: $e');
    }
  }

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

  Future<void> openSaveFolder(SaveFolder folder) => _service.openSaveFolder(folder);

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
      _add(result);
    } on CapturePermissionDenied {
      _permissionDenied = true;
      // 처음이면 시스템 권한 창이 뜬다. 이미 거부했다면 아무 일도 없으니 배너가 설정으로 안내한다.
      await _service.requestPermission();
    } on MissingPluginException {
      // 이 플랫폼의 네이티브 캡처가 아직 없다 (Windows 구현 전).
      debugPrint('Snapdock: native capture is not available on this platform yet');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _add(CaptureResult result) {
    final id = _nextId++;
    storeDir.createSync(recursive: true);
    final String path;
    final String previewPath;
    if (result.kind == CaptureKind.image) {
      path = '${storeDir.path}${Platform.pathSeparator}$id.png';
      File(path).writeAsBytesSync(result.png);
      previewPath = path;
    } else {
      // 영상·GIF 파일은 네이티브가 작업 폴더(= storeDir)에 이미 써 두었다. PNG는 대표 프레임이다.
      path = result.savedPath!;
      previewPath = '${storeDir.path}${Platform.pathSeparator}$id.thumb.png';
      File(previewPath).writeAsBytesSync(result.png);
    }
    _items.insert(
      0,
      CaptureItem(
        id: id,
        kind: result.kind,
        path: path,
        previewPath: previewPath,
        width: result.width,
        height: result.height,
        shape: result.shape,
        createdAt: DateTime.now(),
        duration: result.durationMs == null ? null : Duration(milliseconds: result.durationMs!),
        savedPath: result.kind == CaptureKind.image ? result.savedPath : null,
      ),
    );
    while (_items.length > maxItems) {
      _discard(_items.removeLast());
    }
    _persist();
  }

  /// 디버그 빌드 전용: README 데모에서 방금 캡처한 것처럼 PNG 한 장을 목록에 올린다.
  void addDemoImage(Uint8List png, {required int width, required int height, CaptureShape shape = CaptureShape.rect}) {
    assert(kDebugMode, 'addDemoImage is for debug builds');
    _add(CaptureResult(action: CaptureAction.copy, shape: shape, png: png, width: width, height: height));
    notifyListeners();
  }

  Future<void> copy(CaptureItem item) async {
    if (item.kind == CaptureKind.image) {
      await _service.copyImage(await File(item.path).readAsBytes());
    } else {
      await _service.copyFile(item.path);
    }
  }

  /// 사용자 폴더(사진/동영상)로 저장하고 그 경로를 돌려준다.
  Future<String?> save(CaptureItem item) async {
    if (item.kind == CaptureKind.image) {
      return _service.saveImage(await File(item.path).readAsBytes());
    }
    return _service.saveFile(item.path);
  }

  void remove(CaptureItem item) {
    if (!_items.remove(item)) return;
    _discard(item);
    _persist();
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.toList().forEach(_discard);
    _items.clear();
    _persist();
    notifyListeners();
  }

  /// 항목의 파일을 잠시 뒤에 지운다 (방금 끌어간 파일을 다른 앱이 복사 중일 수 있다).
  void _discard(CaptureItem item) {
    final paths = {item.path, item.previewPath};
    Timer(deleteDelay, () {
      for (final p in paths) {
        try {
          final file = File(p);
          if (file.existsSync() && file.parent.path == storeDir.path) file.deleteSync();
        } catch (_) {
          // 이미 없거나 쓸 수 없으면 넘어간다.
        }
      }
    });
  }

  /// 목록을 `index.json`에 쓴다. 쓰기는 차례대로 한다.
  void _persist() {
    final snapshot = jsonEncode({
      'version': 1,
      'nextId': _nextId,
      'items': [for (final i in _items) i.toJson()],
    });
    _writing = _writing.then((_) async {
      try {
        await storeDir.create(recursive: true);
        final tmp = File('${_indexFile.path}.tmp');
        await tmp.writeAsString(snapshot);
        await tmp.rename(_indexFile.path);
      } catch (e) {
        debugPrint('Snapdock: could not write the capture index: $e');
      }
    });
  }

  /// 테스트에서 쓰기가 끝나길 기다린다.
  @visibleForTesting
  Future<void> flush() => _writing;
}
