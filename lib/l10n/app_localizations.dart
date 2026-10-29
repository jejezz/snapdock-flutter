import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @aboutTooltip.
  ///
  /// In ko, this message translates to:
  /// **'정보'**
  String get aboutTooltip;

  /// No description provided for @aboutVersion.
  ///
  /// In ko, this message translates to:
  /// **'버전 {version} (빌드 {build})'**
  String aboutVersion(String version, String build);

  /// No description provided for @aboutOpenSourceLicenses.
  ///
  /// In ko, this message translates to:
  /// **'오픈소스 라이선스'**
  String get aboutOpenSourceLicenses;

  /// No description provided for @aboutRepository.
  ///
  /// In ko, this message translates to:
  /// **'GitHub'**
  String get aboutRepository;

  /// No description provided for @commonClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get commonClose;

  /// No description provided for @aboutMenuItem.
  ///
  /// In ko, this message translates to:
  /// **'{appName} 정보'**
  String aboutMenuItem(String appName);

  /// No description provided for @themeMenuTooltip.
  ///
  /// In ko, this message translates to:
  /// **'테마'**
  String get themeMenuTooltip;

  /// No description provided for @themeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정 따르기'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ko, this message translates to:
  /// **'라이트'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ko, this message translates to:
  /// **'다크'**
  String get themeDark;

  /// No description provided for @languageMenuTooltip.
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get languageMenuTooltip;

  /// No description provided for @languageSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정 따르기 / System'**
  String get languageSystem;

  /// No description provided for @languageSystemShort.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get languageSystemShort;

  /// No description provided for @aboutTagline.
  ///
  /// In ko, this message translates to:
  /// **'스크린샷과 10초 영상, 독에 담아 바로 꺼내 쓰기'**
  String get aboutTagline;

  /// No description provided for @aboutDescription.
  ///
  /// In ko, this message translates to:
  /// **'사각형, 원형, 창 단위로 스크린샷을 찍고 최대 10초까지 GIF나 MP4로 녹화합니다. 캡처는 항상 위에 떠 있는 작은 썸네일 독에 쌓여 복사하거나 끌어다 쓸 수 있습니다.'**
  String get aboutDescription;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'첫 캡처를 찍어 보세요'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyAction.
  ///
  /// In ko, this message translates to:
  /// **'캡처'**
  String get homeEmptyAction;

  /// No description provided for @updateCheckMenuItem.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 확인'**
  String get updateCheckMenuItem;

  /// No description provided for @updateChecking.
  ///
  /// In ko, this message translates to:
  /// **'업데이트를 확인하는 중…'**
  String get updateChecking;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 버전이 있습니다'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableBody.
  ///
  /// In ko, this message translates to:
  /// **'{appName} {latest} 버전이 나왔습니다. (현재 {current})'**
  String updateAvailableBody(String appName, String current, String latest);

  /// No description provided for @updateReleaseNotes.
  ///
  /// In ko, this message translates to:
  /// **'변경 내용'**
  String get updateReleaseNotes;

  /// No description provided for @updateNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 업데이트'**
  String get updateNow;

  /// No description provided for @updateLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get updateLater;

  /// No description provided for @updateSkipVersion.
  ///
  /// In ko, this message translates to:
  /// **'이 버전 건너뛰기'**
  String get updateSkipVersion;

  /// No description provided for @updateDownloading.
  ///
  /// In ko, this message translates to:
  /// **'내려받는 중…'**
  String get updateDownloading;

  /// No description provided for @updateVerifying.
  ///
  /// In ko, this message translates to:
  /// **'파일을 확인하는 중…'**
  String get updateVerifying;

  /// No description provided for @updateDownloadProgress.
  ///
  /// In ko, this message translates to:
  /// **'{received} / {total}'**
  String updateDownloadProgress(String received, String total);

  /// No description provided for @updateCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get updateCancel;

  /// No description provided for @updateFailedTitle.
  ///
  /// In ko, this message translates to:
  /// **'업데이트하지 못했습니다'**
  String get updateFailedTitle;

  /// No description provided for @updateCheckFailedTitle.
  ///
  /// In ko, this message translates to:
  /// **'업데이트를 확인하지 못했습니다'**
  String get updateCheckFailedTitle;

  /// No description provided for @updateErrorNetwork.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.'**
  String get updateErrorNetwork;

  /// No description provided for @updateErrorChecksum.
  ///
  /// In ko, this message translates to:
  /// **'내려받은 파일이 올바르지 않아 설치하지 않았습니다. 잠시 뒤에 다시 시도해 주세요.'**
  String get updateErrorChecksum;

  /// No description provided for @updateErrorInstall.
  ///
  /// In ko, this message translates to:
  /// **'설치를 시작하지 못했습니다.'**
  String get updateErrorInstall;

  /// No description provided for @updateErrorGeneric.
  ///
  /// In ko, this message translates to:
  /// **'업데이트 서버에서 예상하지 못한 응답을 받았습니다. 잠시 뒤에 다시 시도해 주세요.'**
  String get updateErrorGeneric;

  /// No description provided for @updateUpToDateTitle.
  ///
  /// In ko, this message translates to:
  /// **'최신 버전입니다'**
  String get updateUpToDateTitle;

  /// No description provided for @updateUpToDateBody.
  ///
  /// In ko, this message translates to:
  /// **'{version} 버전을 사용 중입니다.'**
  String updateUpToDateBody(String version);

  /// No description provided for @updateUnavailableTitle.
  ///
  /// In ko, this message translates to:
  /// **'직접 설치해 주세요'**
  String get updateUnavailableTitle;

  /// No description provided for @updateUnavailableBody.
  ///
  /// In ko, this message translates to:
  /// **'{latest} 버전이 있지만 앱에서 자동으로 설치할 수 없습니다. 릴리스 페이지에서 받아 주세요.'**
  String updateUnavailableBody(String latest);

  /// No description provided for @updateOpenReleasePage.
  ///
  /// In ko, this message translates to:
  /// **'릴리스 페이지 열기'**
  String get updateOpenReleasePage;

  /// No description provided for @updateBrowserDownloadTitle.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서 내려받습니다'**
  String get updateBrowserDownloadTitle;

  /// No description provided for @updateBrowserDownloadBody.
  ///
  /// In ko, this message translates to:
  /// **'브라우저가 새 버전 내려받기를 시작합니다. 받은 DMG를 열어 {appName} 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.'**
  String updateBrowserDownloadBody(String appName);

  /// No description provided for @updateMacosOpenedTitle.
  ///
  /// In ko, this message translates to:
  /// **'설치 창이 열렸습니다'**
  String get updateMacosOpenedTitle;

  /// No description provided for @updateMacosOpenedBody.
  ///
  /// In ko, this message translates to:
  /// **'열린 창에서 {appName} 을(를) Applications 폴더로 끌어다 놓아 주세요. 실행 중이면 종료한 뒤 덮어쓰세요.'**
  String updateMacosOpenedBody(String appName);

  /// No description provided for @updateWindowsInstallTitle.
  ///
  /// In ko, this message translates to:
  /// **'설치 프로그램을 열었습니다'**
  String get updateWindowsInstallTitle;

  /// No description provided for @updateWindowsInstallBody.
  ///
  /// In ko, this message translates to:
  /// **'설치하려면 {appName} 을(를) 종료해야 합니다. 설치 프로그램의 안내를 따라 주세요.'**
  String updateWindowsInstallBody(String appName);

  /// No description provided for @updateQuitApp.
  ///
  /// In ko, this message translates to:
  /// **'{appName} 종료'**
  String updateQuitApp(String appName);

  /// No description provided for @updateLinuxInstallTitle.
  ///
  /// In ko, this message translates to:
  /// **'설치를 준비했습니다'**
  String get updateLinuxInstallTitle;

  /// No description provided for @updateLinuxInstallBody.
  ///
  /// In ko, this message translates to:
  /// **'{appName} 을(를) 종료하고 설치합니다. 설치가 끝나면 자동으로 다시 시작됩니다.'**
  String updateLinuxInstallBody(String appName);

  /// No description provided for @updateQuitAndInstall.
  ///
  /// In ko, this message translates to:
  /// **'종료하고 설치'**
  String get updateQuitAndInstall;

  /// No description provided for @updateBusyTitle.
  ///
  /// In ko, this message translates to:
  /// **'지금은 업데이트할 수 없습니다'**
  String get updateBusyTitle;

  /// No description provided for @updateBusyBody.
  ///
  /// In ko, this message translates to:
  /// **'작업이 진행 중입니다. 끝난 뒤에 다시 시도해 주세요.'**
  String get updateBusyBody;

  /// No description provided for @captureHotkeyHint.
  ///
  /// In ko, this message translates to:
  /// **'단축키 {keys}'**
  String captureHotkeyHint(String keys);

  /// No description provided for @capturePermissionTitle.
  ///
  /// In ko, this message translates to:
  /// **'화면 기록 권한이 필요합니다'**
  String get capturePermissionTitle;

  /// No description provided for @capturePermissionBody.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정에서 Snapdock을 허용한 뒤 앱을 다시 시작하세요.'**
  String get capturePermissionBody;

  /// No description provided for @capturePermissionOpen.
  ///
  /// In ko, this message translates to:
  /// **'설정 열기'**
  String get capturePermissionOpen;

  /// No description provided for @thumbCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get thumbCopy;

  /// No description provided for @thumbCopied.
  ///
  /// In ko, this message translates to:
  /// **'복사됨'**
  String get thumbCopied;

  /// No description provided for @thumbRemove.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get thumbRemove;

  /// No description provided for @thumbSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장됨'**
  String get thumbSaved;

  /// No description provided for @dockShrinkTooltip.
  ///
  /// In ko, this message translates to:
  /// **'독으로 줄이기'**
  String get dockShrinkTooltip;

  /// No description provided for @dockExpandTooltip.
  ///
  /// In ko, this message translates to:
  /// **'창으로 펼치기'**
  String get dockExpandTooltip;

  /// No description provided for @dockSizeTooltip.
  ///
  /// In ko, this message translates to:
  /// **'썸네일 크기'**
  String get dockSizeTooltip;

  /// No description provided for @dockCaptureTooltip.
  ///
  /// In ko, this message translates to:
  /// **'캡처'**
  String get dockCaptureTooltip;

  /// No description provided for @dockClearTooltip.
  ///
  /// In ko, this message translates to:
  /// **'모두 지우기'**
  String get dockClearTooltip;

  /// No description provided for @thumbSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get thumbSave;

  /// No description provided for @openPicturesFolder.
  ///
  /// In ko, this message translates to:
  /// **'사진 폴더 열기'**
  String get openPicturesFolder;

  /// No description provided for @openMoviesFolder.
  ///
  /// In ko, this message translates to:
  /// **'동영상 폴더 열기'**
  String get openMoviesFolder;

  /// No description provided for @openFolderTooltip.
  ///
  /// In ko, this message translates to:
  /// **'저장 폴더 열기'**
  String get openFolderTooltip;

  /// No description provided for @settingsTooltip.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settingsTooltip;

  /// No description provided for @settingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In ko, this message translates to:
  /// **'외형'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsMode.
  ///
  /// In ko, this message translates to:
  /// **'모드'**
  String get settingsMode;

  /// No description provided for @settingsModeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get settingsModeSystem;

  /// No description provided for @settingsPalette.
  ///
  /// In ko, this message translates to:
  /// **'색 구성'**
  String get settingsPalette;

  /// No description provided for @settingsPaletteSaturn.
  ///
  /// In ko, this message translates to:
  /// **'새턴'**
  String get settingsPaletteSaturn;

  /// No description provided for @settingsPaletteTeal.
  ///
  /// In ko, this message translates to:
  /// **'청록'**
  String get settingsPaletteTeal;

  /// No description provided for @settingsPaletteAmber.
  ///
  /// In ko, this message translates to:
  /// **'호박'**
  String get settingsPaletteAmber;

  /// No description provided for @settingsPaletteRose.
  ///
  /// In ko, this message translates to:
  /// **'장미'**
  String get settingsPaletteRose;

  /// No description provided for @settingsPaletteSlate.
  ///
  /// In ko, this message translates to:
  /// **'슬레이트'**
  String get settingsPaletteSlate;

  /// No description provided for @settingsPaletteHighContrast.
  ///
  /// In ko, this message translates to:
  /// **'고대비'**
  String get settingsPaletteHighContrast;

  /// No description provided for @settingsRecordingSection.
  ///
  /// In ko, this message translates to:
  /// **'녹화'**
  String get settingsRecordingSection;

  /// No description provided for @settingsRecordingLength.
  ///
  /// In ko, this message translates to:
  /// **'최대 녹화 시간'**
  String get settingsRecordingLength;

  /// No description provided for @settingsSecondsValue.
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초'**
  String settingsSecondsValue(int seconds);

  /// No description provided for @settingsGifNote.
  ///
  /// In ko, this message translates to:
  /// **'GIF는 길수록 용량이 커집니다.'**
  String get settingsGifNote;

  /// No description provided for @settingsFoldersSection.
  ///
  /// In ko, this message translates to:
  /// **'저장 위치'**
  String get settingsFoldersSection;

  /// No description provided for @settingsMetadataSection.
  ///
  /// In ko, this message translates to:
  /// **'스크린샷 정보'**
  String get settingsMetadataSection;

  /// No description provided for @settingsEmbedMetadata.
  ///
  /// In ko, this message translates to:
  /// **'PNG에 촬영 정보 넣기'**
  String get settingsEmbedMetadata;

  /// No description provided for @settingsEmbedMetadataNote.
  ///
  /// In ko, this message translates to:
  /// **'캡처한 시각, Snapdock 버전, OS 버전, 캡처 종류를 PNG 파일 안에 적어 둡니다. 위치와 창 제목은 넣지 않습니다. 파일로 저장하거나 끌어서 붙여넣을 때 함께 나갑니다.'**
  String get settingsEmbedMetadataNote;

  /// No description provided for @settingsImageFolder.
  ///
  /// In ko, this message translates to:
  /// **'이미지 (PNG, GIF)'**
  String get settingsImageFolder;

  /// No description provided for @settingsVideoFolder.
  ///
  /// In ko, this message translates to:
  /// **'영상 (MP4)'**
  String get settingsVideoFolder;

  /// No description provided for @settingsImageFolderDefault.
  ///
  /// In ko, this message translates to:
  /// **'기본 · 사진 폴더의 Snapdock'**
  String get settingsImageFolderDefault;

  /// No description provided for @settingsVideoFolderDefault.
  ///
  /// In ko, this message translates to:
  /// **'기본 · 동영상 폴더의 Snapdock'**
  String get settingsVideoFolderDefault;

  /// No description provided for @settingsChooseFolder.
  ///
  /// In ko, this message translates to:
  /// **'폴더 선택'**
  String get settingsChooseFolder;

  /// No description provided for @settingsResetFolder.
  ///
  /// In ko, this message translates to:
  /// **'기본값'**
  String get settingsResetFolder;

  /// No description provided for @settingsHideInTray.
  ///
  /// In ko, this message translates to:
  /// **'닫으면 트레이로 숨기기'**
  String get settingsHideInTray;

  /// No description provided for @settingsHideInTrayNote.
  ///
  /// In ko, this message translates to:
  /// **'창을 닫아도 앱이 계속 실행되어 단축키로 캡처할 수 있습니다. 시작 프로그램으로 켜면 창 없이 시작합니다.'**
  String get settingsHideInTrayNote;

  /// No description provided for @trayOpenWindow.
  ///
  /// In ko, this message translates to:
  /// **'창 열기'**
  String get trayOpenWindow;

  /// No description provided for @trayOpenDock.
  ///
  /// In ko, this message translates to:
  /// **'독 열기'**
  String get trayOpenDock;

  /// No description provided for @trayCapture.
  ///
  /// In ko, this message translates to:
  /// **'캡처 시작'**
  String get trayCapture;

  /// No description provided for @trayHide.
  ///
  /// In ko, this message translates to:
  /// **'트레이로 숨기기'**
  String get trayHide;

  /// No description provided for @trayQuit.
  ///
  /// In ko, this message translates to:
  /// **'종료'**
  String get trayQuit;

  /// No description provided for @settingsShortcutsSection.
  ///
  /// In ko, this message translates to:
  /// **'단축키'**
  String get settingsShortcutsSection;

  /// No description provided for @settingsShortcutCapture.
  ///
  /// In ko, this message translates to:
  /// **'캡처 시작'**
  String get settingsShortcutCapture;

  /// No description provided for @settingsShortcutDock.
  ///
  /// In ko, this message translates to:
  /// **'독 모드 전환'**
  String get settingsShortcutDock;

  /// No description provided for @settingsShortcutDockNote.
  ///
  /// In ko, this message translates to:
  /// **'트레이에 숨어 있으면 독으로 꺼내고, 창이 보이면 독과 일반 창을 번갈아 바꿉니다. 단축키는 다른 앱을 쓰는 중에도 동작합니다.'**
  String get settingsShortcutDockNote;

  /// No description provided for @settingsGeneralSection.
  ///
  /// In ko, this message translates to:
  /// **'일반'**
  String get settingsGeneralSection;

  /// No description provided for @settingsLaunchAtStartup.
  ///
  /// In ko, this message translates to:
  /// **'컴퓨터를 켤 때 자동으로 시작'**
  String get settingsLaunchAtStartup;

  /// No description provided for @settingsLaunchAtStartupFailed.
  ///
  /// In ko, this message translates to:
  /// **'시작 프로그램 설정을 바꾸지 못했습니다.'**
  String get settingsLaunchAtStartupFailed;

  /// No description provided for @dockCollapseTooltip.
  ///
  /// In ko, this message translates to:
  /// **'접기'**
  String get dockCollapseTooltip;

  /// No description provided for @clearAllButton.
  ///
  /// In ko, this message translates to:
  /// **'모두 지우기'**
  String get clearAllButton;

  /// No description provided for @clearAllTitle.
  ///
  /// In ko, this message translates to:
  /// **'캡처를 모두 지울까요?'**
  String get clearAllTitle;

  /// No description provided for @clearAllBody.
  ///
  /// In ko, this message translates to:
  /// **'독과 목록에서만 지워지고, 저장해 둔 파일은 그대로 남습니다.'**
  String get clearAllBody;

  /// No description provided for @clearAllConfirm.
  ///
  /// In ko, this message translates to:
  /// **'모두 지우기'**
  String get clearAllConfirm;

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @shapeRect.
  ///
  /// In ko, this message translates to:
  /// **'사각형'**
  String get shapeRect;

  /// No description provided for @shapeCircle.
  ///
  /// In ko, this message translates to:
  /// **'원형'**
  String get shapeCircle;

  /// No description provided for @shapeWindow.
  ///
  /// In ko, this message translates to:
  /// **'창'**
  String get shapeWindow;

  /// No description provided for @homeDockIntro.
  ///
  /// In ko, this message translates to:
  /// **'독으로 줄이면 창이 항상 위에 뜨는\n작은 막대가 되어 캡처가 쌓입니다.\n썸네일을 누르면 복사되고,\n다른 앱으로 끌어다 놓을 수도 있습니다.'**
  String get homeDockIntro;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
