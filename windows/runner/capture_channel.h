#ifndef RUNNER_CAPTURE_CHANNEL_H_
#define RUNNER_CAPTURE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

namespace snapdock {

// MethodChannel `art.zoomon.snapdock/capture`를 등록한다. 규격은 docs/WINDOWS.md.
// main_window는 화면 캡처에서 제외한다 (독이 찍히면 안 된다).
void RegisterCaptureChannel(flutter::BinaryMessenger* messenger, HWND main_window);

}  // namespace snapdock

#endif  // RUNNER_CAPTURE_CHANNEL_H_
