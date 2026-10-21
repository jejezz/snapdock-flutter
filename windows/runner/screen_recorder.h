#ifndef RUNNER_SCREEN_RECORDER_H_
#define RUNNER_SCREEN_RECORDER_H_

#include <functional>

#include "capture_common.h"
#include "capture_overlay.h"

namespace snapdock {

struct RecordOutcome {
  bool ok = false;
  std::string error;
  Kind kind = Kind::kVideo;
  std::vector<uint8_t> png;  // 대표 프레임 (가로세로 640 이내)
  int width = 0;
  int height = 0;
  std::wstring path;  // 작업 폴더에 쓴 MP4/GIF
  int duration_ms = 0;
};

using RecordCallback = std::function<void(const RecordOutcome&)>;

// 영역(또는 창 위치)을 녹화한다. 화면 위쪽에 카운트다운 알약이 뜬다. 이미 녹화 중이면 false.
// 최대 길이는 CaptureConfig::max_seconds. 끝나면 callback이 메시지 루프 위에서 불린다.
bool StartRecording(const RecordRequest& request, RecordCallback callback);
// 녹화 중이면 일찍 끝낸다.
void StopRecording();
bool RecordingActive();

}  // namespace snapdock

#endif  // RUNNER_SCREEN_RECORDER_H_
