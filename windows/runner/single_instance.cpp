#include "single_instance.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <iterator>
#include <memory>

namespace snapdock {
namespace {

constexpr wchar_t kMainWindowProp[] = L"art.zoomon.snapdock.main";
constexpr wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

BOOL CALLBACK FindMainWindow(HWND window, LPARAM found) {
  wchar_t cls[64];
  if (::GetClassNameW(window, cls, static_cast<int>(std::size(cls))) == 0) return TRUE;
  if (::wcscmp(cls, kWindowClass) != 0) return TRUE;
  if (::GetPropW(window, kMainWindowProp) == nullptr) return TRUE;
  *reinterpret_cast<HWND*>(found) = window;
  return FALSE;
}

}  // namespace

UINT ActivateInstanceMessage() {
  static const UINT message = ::RegisterWindowMessageW(L"art.zoomon.snapdock.activate");
  return message;
}

void MarkMainWindow(HWND window, flutter::BinaryMessenger* messenger) {
  ::SetPropW(window, kMainWindowProp, reinterpret_cast<HANDLE>(1));
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "art.zoomon.snapdock/instance", &flutter::StandardMethodCodec::GetInstance());
}

void UnmarkMainWindow(HWND window) {
  if (window != nullptr) ::RemovePropW(window, kMainWindowProp);
  g_channel = nullptr;
}

bool ActivateRunningInstance() {
  HWND existing = nullptr;
  ::EnumWindows(FindMainWindow, reinterpret_cast<LPARAM>(&existing));
  if (existing == nullptr) return false;
  // 작업 표시줄에서 실행한 이 프로세스는 포그라운드 권한이 있다. 기존 프로세스가
  // 창을 앞으로 가져올 수 있도록 넘겨 준다.
  DWORD pid = 0;
  ::GetWindowThreadProcessId(existing, &pid);
  if (pid != 0) ::AllowSetForegroundWindow(pid);
  ::PostMessageW(existing, ActivateInstanceMessage(), 0, 0);
  return true;
}

void NotifyActivated() {
  // Dart가 아직 받을 준비가 안 됐으면(시작하는 중) 아무것도 하지 않는다. 시작이 끝나면
  // 앱이 스스로 창을 보여 준다.
  if (g_channel) g_channel->InvokeMethod("activate", nullptr);
}

}  // namespace snapdock
