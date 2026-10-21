<!-- From jejezz/application-release-templates common/tool/readme @ conventions-v1.
     tool/readme/init_readme.py가 만든 파일입니다 — conventions/readme-guide.md 참고.
     {{TODO: …}}를 모두 채우십시오. 하나라도 남아 있으면 tool/readme/check_readme.py가 실패합니다. -->

<p align="center">
  <img src="assets/icon/app_icon.png" width="128" alt="Snapdock 아이콘">
</p>

<h1 align="center">Snapdock</h1>

<p align="center">
  <b>macOS·Windows용 무료 오픈소스 스크린샷·화면 녹화 도구</b> — 사각형·원형·창 단위로 캡처하고 짧은 영상을 GIF나 MP4로 녹화하며, 모든 캡처를 항상 위에 떠 있는 썸네일 독에 모아 둡니다.
</p>

<p align="center">
  <a href="https://github.com/jejezz/snapdock-flutter/releases/latest"><img src="https://img.shields.io/github/v/release/jejezz/snapdock-flutter?style=flat-square&color=4c9dff" alt="최신 릴리스"></a>
  <a href="https://github.com/jejezz/snapdock-flutter/releases"><img src="https://img.shields.io/github/downloads/jejezz/snapdock-flutter/total?style=flat-square&color=7c5cff" alt="다운로드"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20%C2%B7%20Windows-34d399?style=flat-square" alt="macOS · Windows">
  <img src="https://img.shields.io/badge/built%20with-Flutter-02569b?style=flat-square" alt="Flutter">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/jejezz/snapdock-flutter?style=flat-square" alt="MIT 라이선스"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <b>한국어</b>
</p>

<p align="center">
  <img src="docs/screenshots/demo.gif" width="720" alt="Snapdock 데모: 단축키를 누르고 영역을 끌면 캡처가 독에 들어옵니다">
</p>

## 기능

- **네 가지 캡처** — 사각형, 원형(바깥이 투명한 PNG), 창 하나(다른 창에 가려진 부분까지), 화면 전체
- **짧은 녹화** — 영역이나 창을 H.264 MP4 또는 GIF로 녹화합니다. 기본 10초, 설정에서 3~60초로 바꿀 수 있고 카운트다운 알약과 정지 단추가 뜹니다
- **캡처마다 썸네일 독** — 캡처는 항목마다 따로 쌓입니다(S 32px, M 44px, L 64px). 클릭하면 복사, 끌면 다른 앱에 붙여넣기, 우클릭으로 저장·삭제. 독은 항상 위에 떠 있고 알약으로 접히며, 다시 켜도 최근 30개가 돌아옵니다
- **단축키 하나** — macOS `⌥⇧S`, Windows `Alt+Shift+S`로 커서가 있는 모니터에서 선택을 시작합니다. 독과 녹화 알약은 캡처에 찍히지 않습니다
- **라이트·다크, 한국어·English** — 시스템 설정을 따르거나 툴바에서 고를 수 있습니다

<p align="center">
  <img src="docs/screenshots/home.png" width="720" alt="메인 창에 쌓인 캡처 (라이트·다크)">
</p>

<p align="center">
  <img src="docs/screenshots/detail.png" width="720" alt="항상 위 독과 알약으로 접은 모습 (라이트·다크)">
</p>

## 설치

[**Releases**](https://github.com/jejezz/snapdock-flutter/releases/latest)에서 받습니다.

| OS | 파일 |
|---|---|
| macOS 14.0 이상 | `Snapdock-<버전>-macos-universal.dmg` — 열어서 앱을 Applications 폴더로 끌어다 놓으세요 |
| Windows 10/11 (x64) | `Snapdock-<버전>-windows-x64-setup.exe` |

**Windows:** 설치 프로그램에 아직 코드 서명이 없어서 SmartScreen이 "Windows의 PC 보호" 창을 띄웁니다. **추가 정보 → 실행**을 누르세요.

## 동작 방식

독과 설정은 Flutter가 그리고, 캡처·녹화는 MethodChannel 하나(`art.zoomon.snapdock/capture`) 뒤의 네이티브 코드가 맡습니다. macOS는 ScreenCaptureKit과 AVFoundation, Windows는 GDI로 모니터를 얼려 선택하고 창은 `PrintWindow`로, 녹화는 Media Foundation(MP4)과 직접 만든 GIF 인코더로 처리합니다. 독과 녹화 알약은 OS 기능으로 캡처에서 제외해서 결과물에 찍히지 않습니다.

macOS는 처음 캡처할 때 **화면 기록** 권한을 요청합니다. Windows는 권한이 필요 없습니다.

## 개발

```bash
flutter pub get
flutter gen-l10n
flutter run -d macos     # 또는: flutter run -d windows
```

- macOS: macOS 14 SDK가 있는 Xcode.
- Windows: Visual Studio 2022의 "C++를 사용한 데스크톱 개발" 워크로드(Windows SDK에 GDI+와 Media Foundation이 들어 있습니다). Windows 10 버전 2004 이상.
- 프로젝트 메모는 [CLAUDE.md](CLAUDE.md), Windows 네이티브 구현과 채널 규격은 [docs/WINDOWS.md](docs/WINDOWS.md)에 있습니다.

릴리스: `scripts/bump-version.sh patch` → 병합 → `vX.Y.Z` 태그. CI가 모든 플랫폼을 빌드해서 올립니다. 규칙: [application-release-templates/conventions](https://github.com/jejezz/application-release-templates/tree/main/conventions).

## 크레딧

- 글꼴: [서울남산체](https://www.seoul.go.kr/seoul/font.do) (서울특별시)
- 아이콘: [Icons8](https://icons8.com)

## 라이선스

[MIT](LICENSE) © 2026 Jongyun Ahn
