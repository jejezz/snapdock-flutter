# Snapdock

conventions-v1 — jejezz/application-release-templates (`conventions/README.md` step 10)

## 무엇을 하는 앱인가

스크린샷과 최대 10초 화면 녹화(GIF, MP4)를 찍고, 결과를 항상 위에 떠 있는 작은 썸네일 독에 모아 두는 데스크톱 캡처 앱. macOS와 Windows를 지원한다(Flutter).

## 기능 범위

- 스크린샷: 클립보드 복사, 선택한 창, 사각형·원형 영역(원형은 바깥이 투명한 PNG).
- 녹화: 영역·창·화면 전체, 최대 10초(상수 하나로 둔다), GIF 또는 MP4. 앱 단위 녹화는 1차 범위 밖.
- 캡처는 항목마다 따로 저장한다. 독 썸네일을 클릭하면 복사, 끌면 다른 앱에 붙여넣기, 우클릭 메뉴에서 저장·삭제.
- 독은 항상 위, 접으면 알약 모양. 썸네일 크기는 S 32px, M 44px(기본), L 64px.
- 독과 녹화 알약은 캡처 대상에서 제외한다(화면에 찍히면 안 된다).

## GUI 결정 사항

- 선택 오버레이: 바깥 45% 어둡게, 흰색 1.5px 테두리, 앵커 8개(10px 흰색 사각형, 파란 테두리), 크기 배지는 선택 영역 왼쪽 위(`300 × 150`), 툴바는 선택 영역 아래.
- 원형 모드의 앵커는 바깥 사각형 기준.
- 툴바 순서: 사각형, 원형, 창 선택 | 영상, GIF | 복사, 저장, 닫기.
- 종류별 썸네일 색: 사진 파랑, 영상 보라, GIF 초록, 영상·GIF는 모서리 배지.
- 캡처 순간 영역이 0.15초 번쩍이고 썸네일이 독으로 들어간다. 복사 완료는 썸네일에 체크.

## 구현 메모

- 캡처·녹화는 플랫폼 네이티브 코드로 한다. macOS는 ScreenCaptureKit. 스크린샷 API(`SCScreenshotManager`)가 14부터라서 배포 대상을 macOS 14.0으로 올렸다, Windows는 Windows.Graphics.Capture. Flutter 쪽은 MethodChannel로 호출한다.
- macOS는 "화면 기록" 권한이 필요하다. 디버그 빌드는 `.dev` 번들 ID를 써서 릴리스와 권한을 공유하지 않는다.
- 영역 선택 오버레이는 전체 화면 투명 네이티브 창으로 만든다.

## Windows

개발은 Windows에서 이어진다. 네이티브 캡처(채널 `art.zoomon.snapdock/capture`)를 `windows/runner/capture_*.cpp`, `screen_recorder.cpp`에 구현했다(멀티 모니터를 뺀 모든 기능을 Windows에서 확인함). 해야 할 일, 채널 규격, 확인 목록은 [`docs/WINDOWS.md`](docs/WINDOWS.md)에 있다.

## 구현 현황

- 되는 것(macOS): 전역 단축키 ⌥⇧S → 마우스가 있는 디스플레이를 얼린 화면 위에서 영역 선택(8개 앵커, 이동, 크기 배지, 사각형/원형 전환) → 복사 또는 저장(~/Pictures/Snapdock) → 독에 항목 추가. 독 모드는 항상 위 작은 창이며 썸네일 클릭 시 복사, 올리면 ✕, 우클릭 메뉴, S/M/L 크기 순환.
- 창 선택(마우스 아래 창을 강조하고 클릭하면 가려진 부분까지 그 창만 캡처)과 화면 전체(툴바 단추)도 된다.
- 영상·GIF 녹화(macOS): 영역이나 창을 고른 뒤 툴바의 영상/GIF 단추. 최대 길이는 설정에서 3~60초(기본 10초, `CaptureConfig.maxRecordingSeconds`, `ScreenRecorder.swift`), 화면 위쪽 알약에 카운트다운과 정지 단추, 단축키를 한 번 더 눌러도 멈춘다. MP4는 H.264, GIF는 15fps로 녹화한 MP4를 10fps·가로 720px 이하로 변환한다. 파일은 임시 폴더에 두고 저장하면 저장 폴더로 복사한다.
- 펼친 창 앱 바의 맨 왼쪽 단추가 "독으로 줄이기"이고(독 모드가 가장 쓸모 있어서), 캡처가 0개인 첫 화면에는 독 모드를 소개하는 짧은 설명과 같은 이름의 단추가 있다.
- 펼친 창의 목록 위쪽 오른쪽에 "모두 지우기" 단추가 있다(확인 창을 한 번 거친다. 독과 목록에서만 지워지고 사용자 폴더에 저장한 파일은 그대로).
- 설정 창(앱 바의 톱니, 정보 아이콘 바로 왼쪽): 왼쪽 구역 목록 + 오른쪽 내용(application-release-templates `conventions/settings.md`). 화면(테마·색 구성 6종·글자 크기 `text_scale`)과 언어는 앱 바 팝업이 아니라 이 창에서 고른다(`AppSettings`, 키 `theme_mode`·`theme_palette`·`text_scale`·`app_locale`). 앱 고유 구역: 일반, 단축키, 녹화 길이, 이미지(PNG·GIF) 저장 폴더, 영상(MP4) 저장 폴더, 스크린샷 정보. `lib/settings/capture_settings.dart`가 shared_preferences에 저장하고 시작할 때와 바뀔 때마다 채널 `configure`로 네이티브에 보낸다. 폴더가 비어 있으면 기본값 ~/Pictures/Snapdock, ~/Movies/Snapdock.
- 독 완성도(macOS에서 확인 완료): 썸네일을 창 밖으로 끌면 OS 드래그로 넘어가 PNG/MP4/GIF 파일이 나간다(flutter_drag_out v0.5.0). 캡처는 앱 지원 폴더 `captures/`에 파일로 두고 `index.json`에 적어 앱을 다시 켜도 돌아온다(최대 30개, 넘치면 오래된 것부터). 독은 접어서 알약(손잡이·카메라·개수)으로 둘 수 있고 접힘 상태도 기억한다. 캡처 순간 영역이 0.16초 번쩍이고 썸네일은 커지며 들어온다.
- 아직 없는 것: 썸네일이 캡처 영역에서 독으로 날아가는 효과(지금은 독 안에서 커지며 나타나기만 한다), 단축키 설정, Windows 멀티 모니터 확인(`docs/WINDOWS.md`).
- 네이티브: `macos/Runner/CaptureOverlay.swift`(오버레이), `CaptureChannel.swift`(채널). Flutter: `lib/capture/`, `lib/dock/`.

- 독 모드: 마지막에 독으로 끝내면 독으로 시작하고 썸네일 크기(S/M/L)도 기억한다(shared_preferences). 독은 항상 커서가 있는 모니터의 위쪽 가운데(여백 12px)에서 시작하고, 썸네일이 늘면 가로 가운데를 지키며 자란다.

## README 스크린샷과 데모

- 스크린샷(`docs/screenshots/home.png`, `detail.png`)은 격리한 앱 사본에 가짜 캡처를 채워 `capture.sh`·`frame.py`로 만들었다. 원본은 `docs/screenshots/raw/`.
- 데모 GIF는 `tool/readme/demo.sh`가 만든다. Snapdock은 자기 독과 오버레이를 캡처에서 빼므로 직접 찍을 수 없어서, 디버그 빌드가 스스로 독의 사용(새 캡처 도착, 크기 전환, 알약 접기·펼치기)을 재생하는 동안 `screencapture`로 화면 위쪽 띠를 녹화한다(`lib/dev/demo_runner.dart`, 환경 변수 `SNAPDOCK_DEMO=1`). 릴리스 빌드에는 들어가지 않는다(`kDebugMode`, Swift `#if DEBUG`). 화면 속 캡처는 모두 `demo_assets.py`가 그린 샘플이다.
- 녹화 영역은 배경(`DemoBackdrop`)으로 덮어서 뒤의 사용자 화면이 찍히지 않게 하고, 배경이 있는 구간만 잘라 GIF로 만든다.

## 남은 일

- 앱 아이콘의 소품 글리프는 임시 그림(`assets/icon/source_glyph.png`). 고양이는 그대로 두고 Icons8 글리프로 교체한다.
- 멀티 모니터 확인은 macOS 개발 환경에 모니터가 하나뿐이라 미뤄 두었다. Windows에서 확인한다:
  - ⌥⇧S가 커서가 있는 모니터에서 오버레이를 연다.
  - 독이 커서가 있는 모니터의 위쪽 가운데에 뜬다.
  - 모니터마다 배율(Retina/비Retina)이 달라도 잘린 이미지 크기가 배지 숫자와 맞는다.
  - 녹화 영역이 보조 모니터에서도 고른 위치와 같다.
- 영역 녹화, 창 녹화, GIF 화질은 macOS에서 직접 확인했다(모니터 하나).
