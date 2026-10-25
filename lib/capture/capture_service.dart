import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

/// 전역 캡처 단축키의 표시 문구. 등록은 lib/main.dart(Alt+Shift+S)에서 한다.
String get captureShortcutLabel => Platform.isMacOS ? '⌥⇧S' : 'Alt+Shift+S';

enum CaptureShape { rect, circle, window, screen }

enum CaptureAction { copy, save }

/// 캡처의 종류.
enum CaptureKind { image, video, gif }

/// 저장 폴더: 이미지와 GIF는 사진, 영상은 동영상 아래 `Snapdock`.
enum SaveFolder { pictures, movies }

/// 독에 쌓이는 캡처 한 건. 항목마다 따로 보관하고, 내용은 모두 파일로 둔다.
@immutable
class CaptureItem {
  const CaptureItem({
    required this.id,
    required this.kind,
    required this.path,
    required this.previewPath,
    required this.width,
    required this.height,
    required this.shape,
    required this.createdAt,
    this.duration,
    this.savedPath,
  });

  final int id;
  final CaptureKind kind;

  /// 내용 파일: 이미지는 PNG, 영상은 MP4, GIF는 GIF. 끌어다 놓을 때 이 파일이 나간다.
  final String path;

  /// 독에 보여 줄 그림. 이미지는 [path]와 같고, 영상·GIF는 대표 프레임 PNG다.
  final String previewPath;
  final int width;
  final int height;
  final CaptureShape shape;
  final DateTime createdAt;
  final Duration? duration;

  /// 저장 단추로 사용자 폴더에 쓴 경우의 경로.
  final String? savedPath;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'path': path,
        'preview': previewPath,
        'width': width,
        'height': height,
        'shape': shape.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'durationMs': duration?.inMilliseconds,
        'savedPath': savedPath,
      };

  static CaptureItem fromJson(Map<String, Object?> json) => CaptureItem(
        id: json['id']! as int,
        kind: CaptureKind.values.byName(json['kind']! as String),
        path: json['path']! as String,
        previewPath: json['preview']! as String,
        width: json['width']! as int,
        height: json['height']! as int,
        shape: CaptureShape.values.byName(json['shape']! as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']! as int),
        duration: json['durationMs'] == null ? null : Duration(milliseconds: json['durationMs']! as int),
        savedPath: json['savedPath'] as String?,
      );
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

  /// 설정을 네이티브에 알린다. 폴더가 null이면 기본 위치(사진/동영상 폴더의 Snapdock)를 쓴다.
  Future<void> configure({required int maxSeconds, String? imageDir, String? videoDir, String? workDir, bool embedMetadata = false}) =>
      _channel.invokeMethod<void>('configure', {
        'maxSeconds': maxSeconds,
        'imageDir': imageDir,
        'videoDir': videoDir,
        'workDir': workDir,
        'embedMetadata': embedMetadata,
      });

  /// macOS 로그인 항목에 등록돼 있는가.
  Future<bool> launchAtLoginEnabled() async => await _channel.invokeMethod<bool>('launchAtLoginEnabled') ?? false;

  /// macOS 로그인 항목을 켜거나 끄고 결과 상태를 돌려준다.
  Future<bool> setLaunchAtLogin(bool enabled) async =>
      await _channel.invokeMethod<bool>('setLaunchAtLogin', {'enabled': enabled}) ?? false;

  Future<void> openSaveFolder(SaveFolder folder) => _channel.invokeMethod<void>('openFolder', {'kind': folder.name});

  /// 디버그 빌드 전용: README 데모를 녹화할 영역(화면 좌표, 포인트)을 배경으로 덮는다. null이면 걷는다.
  Future<void> demoBackdrop(Rect? rect) {
    assert(kDebugMode, 'demoBackdrop is for debug builds');
    return _channel.invokeMethod<void>(
      'demoBackdrop',
      rect == null ? null : [rect.left, rect.top, rect.width, rect.height],
    );
  }

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
