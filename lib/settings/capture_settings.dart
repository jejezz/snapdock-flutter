import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capture/capture_service.dart';
import 'launch_at_startup.dart';

/// 캡처 설정: 녹화 길이와 저장 위치. 바뀔 때마다 저장하고 네이티브에도 알린다.
class CaptureSettings extends ChangeNotifier {
  CaptureSettings._(this._prefs, this._service, this._workDir, this._maxSeconds, this._imageDir, this._videoDir);

  static const minSeconds = 3;
  static const maxSecondsLimit = 60;
  static const defaultSeconds = 10;

  static const _kSeconds = 'record_max_seconds';
  static const _kImageDir = 'image_folder';
  static const _kVideoDir = 'video_folder';
  static const _kDockMode = 'dock_mode';
  static const _kDockSize = 'dock_size';
  static const _kDockCollapsed = 'dock_collapsed';
  static const _kHideInTray = 'hide_in_tray';
  static const _kEmbedMetadata = 'embed_metadata';

  final SharedPreferences _prefs;
  final CaptureService _service;

  /// 로그인할 때 자동으로 시작하는 설정. 값은 OS가 가지고 있어서 여기에 저장하지 않는다.
  late final LaunchAtStartup launchAtStartup = LaunchAtStartup(_service);

  /// 네이티브가 녹화 파일을 쓰는 작업 폴더. 독이 보관하는 폴더와 같다.
  final String? _workDir;

  int _maxSeconds;
  String? _imageDir;
  String? _videoDir;

  /// 마지막으로 쓴 모드가 독이었는가. 켜면 독으로 시작한다.
  bool get dockMode => _prefs.getBool(_kDockMode) ?? false;

  /// 독 썸네일 크기의 순번(0 작게, 1 보통, 2 크게).
  int get dockSizeIndex => _prefs.getInt(_kDockSize) ?? 1;

  /// 독을 알약 모양으로 접어 두었는가.
  bool get dockCollapsed => _prefs.getBool(_kDockCollapsed) ?? false;

  /// 창을 닫으면 종료하지 않고 트레이로 숨기는가.
  bool get hideInTray => _prefs.getBool(_kHideInTray) ?? false;

  Future<void> setHideInTray(bool value) async {
    await _prefs.setBool(_kHideInTray, value);
    notifyListeners();
  }

  /// 스크린샷 PNG에 앱·시각·OS·캡처 종류를 적어 넣는가. 위치는 넣지 않는다.
  bool get embedMetadata => _prefs.getBool(_kEmbedMetadata) ?? false;

  Future<void> setEmbedMetadata(bool value) async {
    await _prefs.setBool(_kEmbedMetadata, value);
    await apply();
    notifyListeners();
  }

  Future<void> setDockCollapsed(bool value) => _prefs.setBool(_kDockCollapsed, value);

  Future<void> setDockMode(bool value) => _prefs.setBool(_kDockMode, value);

  Future<void> setDockSizeIndex(int index) => _prefs.setInt(_kDockSize, index);

  /// 녹화 최대 길이(초).
  int get maxSeconds => _maxSeconds;

  /// 이미지(PNG)와 GIF를 저장할 폴더. null이면 기본 위치.
  String? get imageDir => _imageDir;

  /// 영상(MP4)을 저장할 폴더. null이면 기본 위치.
  String? get videoDir => _videoDir;

  static Future<CaptureSettings> load(CaptureService service, {String? workDir}) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = CaptureSettings._(
      prefs,
      service,
      workDir,
      (prefs.getInt(_kSeconds) ?? defaultSeconds).clamp(minSeconds, maxSecondsLimit),
      _nonEmpty(prefs.getString(_kImageDir)),
      _nonEmpty(prefs.getString(_kVideoDir)),
    );
    await settings.apply();
    return settings;
  }

  static String? _nonEmpty(String? value) => (value == null || value.isEmpty) ? null : value;

  Future<void> setMaxSeconds(int seconds) async {
    final value = seconds.clamp(minSeconds, maxSecondsLimit);
    if (value == _maxSeconds) return;
    _maxSeconds = value;
    await _prefs.setInt(_kSeconds, value);
    await apply();
    notifyListeners();
  }

  /// null을 주면 기본 위치로 되돌린다.
  Future<void> setImageDir(String? dir) async {
    _imageDir = _nonEmpty(dir);
    await _persist(_kImageDir, _imageDir);
    await apply();
    notifyListeners();
  }

  Future<void> setVideoDir(String? dir) async {
    _videoDir = _nonEmpty(dir);
    await _persist(_kVideoDir, _videoDir);
    await apply();
    notifyListeners();
  }

  Future<void> _persist(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  /// 현재 값을 네이티브 캡처에 보낸다. 네이티브가 없는 플랫폼에서는 조용히 넘어간다.
  Future<void> apply() async {
    try {
      await _service.configure(maxSeconds: _maxSeconds, imageDir: _imageDir, videoDir: _videoDir, workDir: _workDir, embedMetadata: embedMetadata);
    } on MissingPluginException {
      debugPrint('Snapdock: native capture is not available on this platform yet');
    }
  }
}
