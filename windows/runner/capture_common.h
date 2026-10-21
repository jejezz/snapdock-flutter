#ifndef RUNNER_CAPTURE_COMMON_H_
#define RUNNER_CAPTURE_COMMON_H_

// 캡처 코드가 함께 쓰는 타입과 도구. macOS의 CaptureConfig / 결과 타입에 해당한다.

#include <windows.h>
#include <objidl.h>

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

using std::max;
using std::min;
#include <gdiplus.h>

namespace snapdock {

enum class Kind { kImage, kVideo, kGif };
enum class Shape { kRect, kCircle, kWindow, kScreen };
enum class Action { kCopy, kSave };

constexpr int kVideoFps = 30;
constexpr int kGifFps = 10;
constexpr int kGifMaxWidth = 720;

// Dart가 `configure`로 보내 주는 값.
struct CaptureConfig {
  static int max_seconds;
  static std::wstring image_dir;  // 비어 있으면 사진\Snapdock
  static std::wstring video_dir;  // 비어 있으면 동영상\Snapdock
  static std::wstring work_dir;   // 비어 있으면 %TEMP%\Snapdock

  static std::wstring SaveFolder(bool movies);
  static std::wstring WorkFolder();
};

// 위에서 아래로 쌓인 BGRA 픽셀 (stride = width * 4). 알파는 straight(비곱셈)다.
struct Bgra {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> pixels;
};

void StartGdiplus();

std::string ToUtf8(const std::wstring& wide);
std::wstring ToWide(const std::string& utf8);

std::vector<uint8_t> EncodePng(const Bgra& image);
bool DecodePng(const std::vector<uint8_t>& png, Bgra* out);
// 긴 변이 max_side 이하가 되도록 줄인 PNG. 이미 작으면 그대로 인코딩한다.
std::vector<uint8_t> EncodeThumbnailPng(const Bgra& image, int max_side);

// `yyyy-MM-dd HH.mm.ss`
std::wstring Timestamp();
bool EnsureDirectory(const std::wstring& path);
std::wstring JoinPath(const std::wstring& dir, const std::wstring& name);

// 우리 프로세스의 창은 화면 캡처에 찍히지 않게 한다 (Windows 10 2004+).
void ExcludeFromCapture(HWND hwnd);

}  // namespace snapdock

#endif  // RUNNER_CAPTURE_COMMON_H_
