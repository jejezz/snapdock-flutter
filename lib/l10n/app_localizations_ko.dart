// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get aboutTooltip => '정보';

  @override
  String aboutVersion(String version, String build) {
    return '버전 $version (빌드 $build)';
  }

  @override
  String get aboutOpenSourceLicenses => '오픈소스 라이선스';

  @override
  String get aboutRepository => 'GitHub';

  @override
  String get commonClose => '닫기';

  @override
  String aboutMenuItem(String appName) {
    return '$appName 정보';
  }

  @override
  String get themeMenuTooltip => '테마';

  @override
  String get themeSystem => '시스템 설정 따르기';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get languageMenuTooltip => '언어';

  @override
  String get languageSystem => '시스템 설정 따르기 / System';

  @override
  String get languageSystemShort => '시스템';

  @override
  String get aboutTagline => '스크린샷과 10초 영상, 독에 담아 바로 꺼내 쓰기';

  @override
  String get aboutDescription =>
      '사각형, 원형, 창 단위로 스크린샷을 찍고 최대 10초까지 GIF나 MP4로 녹화합니다. 캡처는 항상 위에 떠 있는 작은 썸네일 독에 쌓여 복사하거나 끌어다 쓸 수 있습니다.';

  @override
  String get homeEmptyTitle => '첫 캡처를 찍어 보세요';

  @override
  String get homeEmptyAction => '캡처';

  @override
  String get updateCheckMenuItem => '업데이트 확인';

  @override
  String get updateChecking => '업데이트를 확인하는 중…';

  @override
  String get updateAvailableTitle => '새 버전이 있습니다';

  @override
  String updateAvailableBody(String appName, String current, String latest) {
    return '$appName $latest 버전이 나왔습니다. (현재 $current)';
  }

  @override
  String get updateReleaseNotes => '변경 내용';

  @override
  String get updateNow => '지금 업데이트';

  @override
  String get updateLater => '나중에';

  @override
  String get updateSkipVersion => '이 버전 건너뛰기';

  @override
  String get updateDownloading => '내려받는 중…';

  @override
  String get updateVerifying => '파일을 확인하는 중…';

  @override
  String updateDownloadProgress(String received, String total) {
    return '$received / $total';
  }

  @override
  String get updateCancel => '취소';

  @override
  String get updateFailedTitle => '업데이트하지 못했습니다';

  @override
  String get updateCheckFailedTitle => '업데이트를 확인하지 못했습니다';

  @override
  String get updateErrorNetwork =>
      '업데이트 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.';

  @override
  String get updateErrorChecksum =>
      '내려받은 파일이 올바르지 않아 설치하지 않았습니다. 잠시 뒤에 다시 시도해 주세요.';

  @override
  String get updateErrorInstall => '설치를 시작하지 못했습니다.';

  @override
  String get updateErrorGeneric =>
      '업데이트 서버에서 예상하지 못한 응답을 받았습니다. 잠시 뒤에 다시 시도해 주세요.';

  @override
  String get updateUpToDateTitle => '최신 버전입니다';

  @override
  String updateUpToDateBody(String version) {
    return '$version 버전을 사용 중입니다.';
  }

  @override
  String get updateUnavailableTitle => '직접 설치해 주세요';

  @override
  String updateUnavailableBody(String latest) {
    return '$latest 버전이 있지만 앱에서 자동으로 설치할 수 없습니다. 릴리스 페이지에서 받아 주세요.';
  }

  @override
  String get updateOpenReleasePage => '릴리스 페이지 열기';

  @override
  String get updateBrowserDownloadTitle => '브라우저에서 내려받습니다';

  @override
  String updateBrowserDownloadBody(String appName) {
    return '브라우저가 새 버전 내려받기를 시작합니다. 받은 DMG를 열어 $appName 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.';
  }

  @override
  String get updateMacosOpenedTitle => '설치 창이 열렸습니다';

  @override
  String updateMacosOpenedBody(String appName) {
    return '열린 창에서 $appName 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.';
  }

  @override
  String get updateWindowsInstallTitle => '설치 프로그램을 열었습니다';

  @override
  String updateWindowsInstallBody(String appName) {
    return '설치하려면 $appName 을(를) 종료해야 합니다. 설치 프로그램의 안내를 따라 주세요.';
  }

  @override
  String updateQuitApp(String appName) {
    return '$appName 종료';
  }

  @override
  String get updateLinuxInstallTitle => '설치를 준비했습니다';

  @override
  String updateLinuxInstallBody(String appName) {
    return '$appName 을(를) 종료하고 설치합니다. 설치가 끝나면 자동으로 다시 시작됩니다.';
  }

  @override
  String get updateQuitAndInstall => '종료하고 설치';

  @override
  String get updateBusyTitle => '지금은 업데이트할 수 없습니다';

  @override
  String get updateBusyBody => '작업이 진행 중입니다. 끝난 뒤에 다시 시도해 주세요.';

  @override
  String get captureHotkeyHint => '단축키 ⌥⇧S';

  @override
  String get capturePermissionTitle => '화면 기록 권한이 필요합니다';

  @override
  String get capturePermissionBody => '시스템 설정에서 Snapdock을 허용한 뒤 앱을 다시 시작하세요.';

  @override
  String get capturePermissionOpen => '설정 열기';

  @override
  String get thumbCopy => '복사';

  @override
  String get thumbCopied => '복사됨';

  @override
  String get thumbRemove => '삭제';

  @override
  String get thumbSaved => '저장됨';

  @override
  String get dockShrinkTooltip => '독으로 줄이기';

  @override
  String get dockExpandTooltip => '창으로 펼치기';

  @override
  String get dockSizeTooltip => '썸네일 크기';

  @override
  String get dockCaptureTooltip => '캡처';

  @override
  String get dockClearTooltip => '모두 지우기';

  @override
  String get thumbSave => '저장';

  @override
  String get openPicturesFolder => '사진 폴더 열기';

  @override
  String get openMoviesFolder => '동영상 폴더 열기';

  @override
  String get openFolderTooltip => '저장 폴더 열기';

  @override
  String get settingsTooltip => '설정';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsRecordingSection => '녹화';

  @override
  String get settingsRecordingLength => '최대 녹화 시간';

  @override
  String settingsSecondsValue(int seconds) {
    return '$seconds초';
  }

  @override
  String get settingsGifNote => 'GIF는 길수록 용량이 커집니다.';

  @override
  String get settingsFoldersSection => '저장 위치';

  @override
  String get settingsImageFolder => '이미지 (PNG, GIF)';

  @override
  String get settingsVideoFolder => '영상 (MP4)';

  @override
  String get settingsImageFolderDefault => '기본 · 사진 폴더의 Snapdock';

  @override
  String get settingsVideoFolderDefault => '기본 · 동영상 폴더의 Snapdock';

  @override
  String get settingsChooseFolder => '폴더 선택';

  @override
  String get settingsResetFolder => '기본값';
}
