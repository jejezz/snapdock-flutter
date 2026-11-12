#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

namespace snapdock {

// 이미 실행 중인 인스턴스를 깨울 때 쓰는 창 메시지(RegisterWindowMessage).
UINT ActivateInstanceMessage();

// 주 창에 Snapdock 표식을 붙이고 채널 `art.zoomon.snapdock/instance`를 연다.
// 다른 Flutter 앱도 창 클래스 이름이 같으므로 클래스만으로 찾으면 남의 창을 띄울 수 있다.
void MarkMainWindow(HWND window, flutter::BinaryMessenger* messenger);
void UnmarkMainWindow(HWND window);

// 실행 중인 Snapdock 주 창을 찾아 깨우라고 알린다. 찾았으면 true.
bool ActivateRunningInstance();

// 주 창이 ActivateInstanceMessage()를 받았을 때 부른다. Dart에 `activate`를 보낸다.
void NotifyActivated();

}  // namespace snapdock

#endif  // RUNNER_SINGLE_INSTANCE_H_
