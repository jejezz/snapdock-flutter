import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum CaptureShape { rect, circle, window, screen }

enum CaptureAction { copy, save }

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
    this.savedPath,
  });

  final int id;
  final Uint8List png;
  final int width;
  final int height;
  final CaptureShape shape;
  final DateTime createdAt;

  /// 저장 단추로 파일에 쓴 경우의 경로.
  final String? savedPath;
}

/// 네이티브 캡처 채널 (macos/Runner/CaptureChannel.swift).
class CaptureService {
  CaptureService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('art.zoomon.snapdock/capture');

  final MethodChannel _channel;

  Future<bool> hasPermission() async => await _channel.invokeMethod<bool>('permissionStatus') ?? false;

  Future<bool> requestPermission() async => await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<void> openPermissionSettings() => _channel.invokeMethod<void>('openPermissionSettings');

  Future<void> copyImage(Uint8List png) => _channel.invokeMethod<void>('copyImage', {'png': png});

  /// 영역을 고르게 한다. 사용자가 취소하면 null.
  /// 권한이 없으면 [CapturePermissionDenied]를 던진다.
  Future<CaptureResult?> captureRegion({required CaptureShape shape}) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('captureRegion', {'shape': shape.name});
      if (raw == null) return null;
      return CaptureResult(
        action: CaptureAction.values.byName(raw['action']! as String),
        shape: CaptureShape.values.byName(raw['shape']! as String),
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
    this.savedPath,
  });

  final CaptureAction action;
  final CaptureShape shape;
  final Uint8List png;
  final int width;
  final int height;
  final String? savedPath;
}

class CapturePermissionDenied implements Exception {
  const CapturePermissionDenied();
}
