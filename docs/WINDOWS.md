# Windows에서 이어서 하기

macOS에서 만든 Snapdock을 Windows로 가져오는 작업의 인수인계 문서다. 지금 상태, 해야 할 일, 채널 규격, 확인 목록을 한곳에 모았다. 앱 전반의 결정 사항은 [`CLAUDE.md`](../CLAUDE.md)에 있다.

## 지금 상태

- Flutter 쪽(`lib/`)은 대부분 플랫폼과 무관하고 Windows에서도 그대로 돈다: 독, 설정 창, 캡처 목록 보관, 끌어다 놓기(`flutter_drag_out`은 Windows OLE `DoDragDrop` 지원, beta), 전역 단축키(`hotkey_manager`), 폴더 선택(`file_selector`).
- **네이티브 캡처를 구현했다(빌드만 확인, 실기기 동작 확인 전).** `windows/runner/`의 `capture_channel.cpp`(채널·클립보드·저장), `capture_overlay.cpp`(얼린 화면 위 영역/창/원형 선택, 툴바, 스크린샷), `screen_recorder.cpp`(GDI 영역 녹화 → Media Foundation H.264 MP4 또는 직접 만든 GIF 인코더, 카운트다운 알약), `capture_common.cpp`(설정·PNG·경로). `flutter build windows --debug`가 통과한다. 우리 창(독·알약)은 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`로 캡처에서 뺀다(Windows 10 2004 이상).
- 구현 방식은 아래 표의 "후보"와 조금 다르다: 얼리기·녹화는 DXGI/Graphics.Capture 대신 GDI `BitBlt`, 창 한 장 캡처는 `PrintWindow(PW_RENDERFULLCONTENT)`, 창 녹화는 창 위치를 따라가며 그 영역을 뜬다(다른 창이 위에 겹치면 같이 찍힌다). GIF는 15fps→10fps 변환 대신 처음부터 10fps, 가로 720px 이하, 고정 252색 팔레트+순서 디더링으로 쓴다.
- Windows 릴리스 파이프라인(Inno Setup 설치 파일)은 이미 동작한다. `v0.1.0-rc.2`에서 `build-windows`가 성공했다.
- 앱은 macOS와 Windows만 지원한다. Linux 폴더는 없고 릴리스 워크플로에서도 뺐다.

## 해야 할 일 (순서 제안, 1~4는 구현됨 — 실기기 확인이 남았다)

1. **채널 뼈대**: `windows/runner/`에 `CaptureChannel`을 만들어 아래 규격의 메서드를 등록한다. `flutter_window.cpp`의 `OnCreate`에서 `flutter_controller_->engine()`으로 `MethodChannel`을 연결한다. 먼저 `configure`, `permissionStatus`(항상 true), `openFolder`, `copyImage`, `saveImage`처럼 쉬운 것부터 채우면 설정 창과 폴더 열기가 바로 살아난다.
2. **영역 선택 오버레이 + 스크린샷**: 가장 큰 덩어리. macOS의 [`CaptureOverlay.swift`](../macos/Runner/CaptureOverlay.swift)와 같은 역할이다.
3. **창 선택과 화면 전체**.
4. **녹화(영상·GIF)**: macOS의 [`ScreenRecorder.swift`](../macos/Runner/ScreenRecorder.swift)와 같은 역할이다.
5. **멀티 모니터와 배율 확인**: 아래 확인 목록 참고. macOS 개발 환경에는 모니터가 하나뿐이어서 Windows에서 하기로 했다.

### 구현 방향 (제안, 확정 아님)

| 기능 | macOS에서 쓴 것 | Windows 후보 |
|---|---|---|
| 화면을 얼리고 그 위에서 선택 | ScreenCaptureKit `SCScreenshotManager`로 디스플레이 한 장을 찍고 풀스크린 `NSWindow`에 그린다 | DXGI Desktop Duplication 또는 GDI `BitBlt`로 얼린 뒤, 레이어드 풀스크린 창(`WS_EX_TOPMOST`, `WS_EX_TOOLWINDOW`)에 그린다 |
| 우리 앱 창 제외 | 필터의 `excludingApplications` | 얼리기 전에 우리 창을 숨기거나 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` |
| 창 목록(앞에서부터) | `SCShareableContent.windows` + `CGWindowListCopyWindowInfo` 순서 | `EnumWindows`(Z 순서)로 보이는 최상위 창만 |
| 창 하나만 찍기(가려져도) | `SCContentFilter(desktopIndependentWindow:)` | Windows.Graphics.Capture의 `GraphicsCaptureItem::CreateFromWindow`, 또는 `PrintWindow(PW_RENDERFULLCONTENT)` |
| 녹화 | `SCStream` + `AVAssetWriter`(H.264 MP4) | Windows.Graphics.Capture + Media Foundation `IMFSinkWriter`(H.264) |
| GIF | 녹화한 MP4에서 프레임을 뽑아 `CGImageDestination` | MP4에서 프레임을 뽑아 WIC GIF 인코더, 또는 녹화 중 프레임을 직접 모아 인코딩 |
| 클립보드 | `NSPasteboard` PNG, 파일 URL | `RegisterClipboardFormat("PNG")` + `CF_DIBV5`, 파일은 `CF_HDROP` |
| 툴바 | `NSVisualEffectView` + `NSButton`(SF Symbols) | 오버레이 창 위에 직접 그리거나 별도 레이어드 창. 아이콘은 Segoe Fluent Icons |

Windows.Graphics.Capture는 Windows 10 1903 이상이 필요하다. 설치 파일의 최소 버전을 정할 때 같이 정한다.

## 채널 규격 `art.zoomon.snapdock/capture`

Dart 쪽은 [`lib/capture/capture_service.dart`](../lib/capture/capture_service.dart), macOS 쪽은 [`macos/Runner/CaptureChannel.swift`](../macos/Runner/CaptureChannel.swift)다. Windows도 같은 규격을 따르면 Dart는 바꿀 필요가 없다.

| 메서드 | 인자 | 반환 | 설명 |
|---|---|---|---|
| `permissionStatus` | – | `bool` | 화면 기록 권한. Windows는 항상 `true` |
| `requestPermission` | – | `bool` | Windows는 `true` |
| `openPermissionSettings` | – | – | Windows는 아무것도 안 해도 된다 |
| `captureRegion` | `shape`: `rect`/`circle`/`window`/`screen` | `null`(취소) 또는 맵 | 오버레이를 띄우고 사용자가 끝낼 때까지 기다린다. 녹화를 고르면 녹화가 끝날 때까지도 기다린다 |
| `copyImage` | `png`: 바이트 | – | PNG를 클립보드에 |
| `copyFile` | `path` | – | 파일을 클립보드에(영상·GIF) |
| `saveImage` | `png` | 저장한 경로 또는 `null` | 이미지 폴더에 `Snapdock yyyy-MM-dd HH.mm.ss.png` |
| `saveFile` | `path` | 저장한 경로 또는 `null` | GIF는 이미지 폴더, MP4는 영상 폴더로 복사 |
| `openFolder` | `kind`: `pictures`/`movies` | – | 저장 폴더를 탐색기로. 없으면 만든다 |
| `stopRecording` | – | – | 녹화 중이면 일찍 끝낸다. 아니면 무시 |
| `configure` | `maxSeconds`(int), `imageDir`, `videoDir`, `workDir`(문자열 또는 null) | – | 시작할 때와 설정이 바뀔 때마다 온다. 폴더가 null이면 기본 위치 |

`captureRegion`이 돌려주는 맵:

```
action:      "copy" | "save"         이미지일 때 어떤 단추로 끝냈는가
shape:       "rect" | "circle" | "window" | "screen"
kind:        "image" | "video" | "gif"
png:         바이트   이미지면 결과 PNG(원형은 바깥이 투명), 영상·GIF면 대표 프레임 PNG(가로세로 640 이내)
width/height 픽셀 크기
path:        문자열   action이 save인 이미지는 저장한 경로, 영상·GIF는 workDir에 쓴 파일 경로
durationMs:  정수     영상·GIF의 실제 녹화 길이
```

- 이미지에서 `action: "copy"`면 네이티브가 직접 클립보드에 넣고, `"save"`면 이미지 폴더에 저장한 뒤 `path`를 채운다. 영상·GIF는 클립보드에 자동으로 넣지 않는다.
- 오류 코드: 권한이 없으면 `permission_denied`, 그 밖에는 `capture_failed`.
- 기본 저장 폴더는 이미지 `%USERPROFILE%\Pictures\Snapdock`, 영상 `%USERPROFILE%\Videos\Snapdock`이다(macOS는 `~/Pictures/Snapdock`, `~/Movies/Snapdock`). 설정 창의 문구는 "사진 폴더의 Snapdock", "동영상 폴더의 Snapdock"이라 Windows에서도 어색하지 않다.
- `workDir`은 Dart가 정한 앱 지원 폴더의 `captures/`다. 녹화 파일(MP4/GIF)을 처음부터 여기에 쓰면 Dart가 그대로 목록에 올린다. 파일 이름은 `Snapdock yyyy-MM-dd HH.mm.ss.mp4`/`.gif`.
- 녹화 최대 길이는 `configure`로 받은 `maxSeconds`다(기본 10, 설정에서 3~60). 하드코딩하지 않는다.

## 오버레이와 녹화가 지켜야 하는 동작

[`CLAUDE.md`](../CLAUDE.md)의 "GUI 결정 사항"과 같다. 요약:

- 단축키 한 번으로 마우스가 있는 모니터를 얼리고 그 위에서 고른다. 바깥은 45% 어둡게, 선택 영역은 흰색 1.5px 테두리, 앵커 8개(10px 흰색 사각형에 파란 테두리), 선택 영역 왼쪽 위에 `300 × 150` 크기 배지(픽셀 기준).
- 툴바는 처음부터 화면 아래 가운데에 있고, 영역을 고르면 영역 아래(공간이 없으면 위)로 옮겨 간다: 사각형, 원형, 창, 화면 전체 | (선택이 있으면) 영상, GIF | 복사, 저장 | 닫기. Esc는 취소, Return은 복사.
- 창 모드는 마우스 아래 창을 파란 3px 테두리로 강조하고(배지에 앱 이름 — 창 제목 · 크기), 클릭하면 그 창을 고정한다. 고정한 뒤 사각형/원형으로 바꾸면 그 영역을 이어서 다듬을 수 있다.
- 이미지를 찍으면 영역이 0.16초 하얗게 번쩍인 뒤 닫힌다.
- 녹화 중에는 화면 위쪽에 알약이 뜬다: 깜빡이는 빨간 점, `00:03 / 00:10`, 정지 단추. 알약과 독은 녹화에 찍히면 안 된다.
- 영상은 H.264 MP4. GIF는 15fps로 녹화한 MP4를 10fps, 가로 720px 이하로 변환한다(`RecordingLimits`).

## Windows 개발 환경

```
flutter doctor            # Visual Studio 2022의 "C++를 사용한 데스크톱 개발"이 필요
git clone https://github.com/jejezz/snapdock-flutter.git
cd snapdock-flutter
flutter pub get
flutter gen-l10n
flutter run -d windows
```

- 설치 파일을 로컬에서 만들려면 Inno Setup 6이 필요하다([`installer/windows/app.iss`](../installer/windows/app.iss)). 릴리스 CI가 하므로 평소에는 필요 없다.
- C++/WinRT를 쓰면 `windows/runner/CMakeLists.txt`에 링크 설정이 필요하다.
- Flutter 3.47.1(CI와 같은 버전)을 쓴다.

## Windows에서 확인할 목록

macOS에서 아직 확인하지 못한 것과 Windows에서 처음 확인할 것이다.

**멀티 모니터** (macOS 환경에 모니터가 하나뿐이었다)
- 단축키를 누르면 커서가 있는 모니터에서 오버레이가 열린다.
- 독이 커서가 있는 모니터의 위쪽 가운데에 뜬다(`DockWindow._topCenter`, `screen_retriever` 사용). 작업 표시줄이 위나 옆에 있어도 가려지지 않는다.
- 모니터마다 배율(100%, 150% 등)이 달라도 잘린 이미지 크기가 배지 숫자와 맞는다.
- 보조 모니터에서도 영역 녹화 위치가 고른 곳과 같다.

**Flutter 쪽 동작**
- 전역 단축키 ⌥⇧S는 Windows에서 Alt+Shift+S다(`hotkey_manager`). 다른 앱과 겹치는지 확인한다.
- 독 모드: 항상 위, 제목 줄 숨김, 창 크기 조절(`window_manager`). 알약으로 접기와 펼치기.
- 끌어다 놓기: 독 썸네일을 탐색기, 메신저, 메모 앱에 놓는다(PNG, MP4, GIF). `flutter_drag_out`의 Windows 구현은 beta라 실기기 확인이 처음이다.
- 앱 지원 폴더(`getApplicationSupportDirectory`)에 `captures/index.json`이 생기고, 껐다 켜도 목록과 독/알약 상태가 돌아온다.
- 폴더 선택(`file_selector`)과 설정 저장.
- 한글 경로, 공백이 있는 경로에서 저장과 복사.

**macOS에서는 확인을 마쳤다**: 영역·창 녹화, GIF 화질, 독의 끌어다 놓기, 캡처 목록 보관, 알약 접기, 캡처 효과. 위 항목들은 Windows에서 같은 동작이 나오는지 보는 것이다.

## 남은 일 (플랫폼 공통)

- 앱 아이콘의 소품 글리프는 임시 그림이다. Icons8 글리프로 바꾼다(`assets/icon/source_glyph.png`, 고양이는 유지).
- README의 Features, How it works, 스크린샷, 데모 GIF는 기능이 갖춰진 뒤 채운다. 첫 정식 릴리스(`v0.1.0`, rc가 아닌 것) 전에 필수다.
- 단축키 설정 UI.
- 썸네일이 캡처 영역에서 독으로 날아가는 효과(지금은 독 안에서 커지며 나타난다).
