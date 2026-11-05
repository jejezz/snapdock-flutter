#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 한 번에 하나만 실행한다. 전역 단축키는 먼저 등록한 프로세스 하나만 가질 수 있어서,
  // 두 번째 인스턴스가 뜨면 단축키가 조용히 죽는다. 업데이트 직후처럼 옛 인스턴스가
  // 막 종료되는 중일 수 있으니 잠깐 기다렸다가, 그래도 살아 있으면 그 창을 앞으로 가져오고 끝낸다.
  HANDLE instance_mutex = ::CreateMutexW(nullptr, TRUE, L"Local\\art.zoomon.snapdock.single-instance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    DWORD wait = ::WaitForSingleObject(instance_mutex, 5000);
    if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
      HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
      if (existing != nullptr) {
        ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
        ::SetForegroundWindow(existing);
      }
      ::CloseHandle(instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  {
  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Snapdock", origin, size)) {
    ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  }  // window 소멸(엔진 해제)이 끝난 뒤에 뮤텍스를 놓는다.

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
