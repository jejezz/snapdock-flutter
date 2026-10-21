#ifndef RUNNER_CAPTURE_OVERLAY_H_
#define RUNNER_CAPTURE_OVERLAY_H_

#include <functional>

#include "capture_common.h"

namespace snapdock {

struct ImageOutcome {
  Action action = Action::kCopy;
  Shape shape = Shape::kRect;
  std::vector<uint8_t> png;
  int width = 0;
  int height = 0;
};

// 영역(화면 좌표) 또는 창 하나를 녹화하라는 요청.
struct RecordRequest {
  Kind kind = Kind::kVideo;
  RECT region = {};
  HWND window = nullptr;  // null이 아니면 이 창의 위치를 따라간다
};

struct OverlayResult {
  enum Type { kCancel, kImage, kRecord } type = kCancel;
  ImageOutcome image;
  RecordRequest record;
};

using OverlayCallback = std::function<void(const OverlayResult&)>;

// 커서가 있는 모니터를 얼리고 그 위에서 영역을 고르게 한다. 이미 떠 있으면 false.
// 결과는 메시지 루프를 도는 동안 callback으로 온다 (오버레이 창이 닫힌 뒤).
bool RunOverlay(Shape initial, OverlayCallback callback);
bool OverlayActive();

}  // namespace snapdock

#endif  // RUNNER_CAPTURE_OVERLAY_H_
