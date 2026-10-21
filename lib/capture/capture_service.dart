import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum CaptureShape { rect, circle, window, screen }

enum CaptureAction { copy, save }

/// 캡처의 종류. 영상과 GIF는 [CaptureItem.filePath]에 파일이 있다.
enum CaptureKind { image, video, gif }

/// 저장 폴더: 이미지와 GIF는 사진, 영상은 동영상 아래 `Snapdock`.
enum SaveFolder { pictures, movies }

/// 독에 쌓이는 캡처 한 건. 항목마다 따로 보관한다.
@immutable
class CaptureItem {
  const CaptureItem({
    required this.id,
    required this.png,
    required this.width,
    required this.height,
    required this.shape,
    required this.createdAt,
    this.kind = CaptureKind.image,
    this.filePath,
    this.duration,
    this.savedPath,
  });

  final int id;
  final CaptureKind kind;

  /// 이미지면 결과 PNG, 영상·GIF면 썸네일 PNG.
  final Uint8List png;
  final int width;
  final int height;
  final CaptureShape shape;
  final DateTime createdAt;

  /// 영상·GIF 파일(임시 폴더). 저장하면 사용자 폴더로 복사한다.
  final String? filePath;
  final Duration? duration;

  /// 저장 단추로 파일에 쓴 경우의 경로.
  final String? savedPath;
}

/// 네이티브 캡처 채널 (macos/Runner/CaptureChannel.swift).
class CaptureService {
  CaptureService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('art.zoomon.snapdock/capture');

  final MethodChannel _channel;

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('permissionStatus') ?? false;

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<void> openPermissionSettings() =>
      _channel.invokeMethod<void>('openPermissionSettings');

  Future<void> copyImage(Uint8List png) =>
      _channel.invokeMethod<void>('copyImage', {'png': png});

  Future<void> copyFile(String path) =>
      _channel.invokeMethod<void>('copyFile', {'path': path});

  /// 저장한 파일 경로를 돌려준다. 실패하면 null.
  Future<String?> saveImage(Uint8List png) =>
      _channel.invokeMethod<String>('saveImage', {'png': png});

  Future<String?> saveFile(String path) =>
      _channel.invokeMethod<String>('saveFile', {'path': path});

  Future<void> openSaveFolder(SaveFolder folder) => _channel.invokeMethod<void>('openFolder', {'kind': folder.name});

  /// 녹화 중이면 일찍 끝낸다. 아니면 아무 일도 없다.
  Future<void> stopRecording() => _channel.invokeMethod<void>('stopRecording');

  /// 영역을 고르게 한다. 사용자가 취소하면 null.
  /// 권한이 없으면 [CapturePermissionDenied]를 던진다.
  Future<CaptureResult?> captureRegion({required CaptureShape shape}) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'captureRegion',
        {'shape': shape.name},
      );
      if (raw == null) return null;
      return CaptureResult(
        action: CaptureAction.values.byName(raw['action']! as String),
        shape: CaptureShape.values.byName(raw['shape']! as String),
        kind: CaptureKind.values.byName(raw['kind'] as String? ?? 'image'),
        durationMs: raw['durationMs'] as int?,
        png: raw['png']! as Uint8List,
        width: raw['width']! as int,
        height: raw['height']! as int,
        savedPath: raw['path'] as String?,
      );
    } on PlatformException catch (e) {
      if (e.code == 'permission_denied') throw const CapturePermissionDenied();
      rethrow;
    }
  }
}

class CaptureResult {
  const CaptureResult({
    required this.action,
    required this.shape,
    required this.png,
    required this.width,
    required this.height,
    this.kind = CaptureKind.image,
    this.durationMs,
    this.savedPath,
  });

  final CaptureAction action;
  final CaptureKind kind;
  final int? durationMs;
  final CaptureShape shape;
  final Uint8List png;
  final int width;
  final int height;

  /// 이미지를 저장했으면 그 파일, 영상·GIF면 임시 파일 경로.
  final String? savedPath;
}

class CapturePermissionDenied implements Exception {
  const CapturePermissionDenied();
}
