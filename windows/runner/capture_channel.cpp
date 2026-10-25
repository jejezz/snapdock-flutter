#include "capture_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>

#include <memory>

#include "capture_common.h"
#include "capture_overlay.h"
#include "screen_recorder.h"

namespace snapdock {
namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = flutter::MethodResult<EncodableValue>;

const EncodableMap* Args(const flutter::MethodCall<EncodableValue>& call) {
  return std::get_if<EncodableMap>(call.arguments());
}

const EncodableValue* Find(const EncodableMap* map, const char* key) {
  if (!map) return nullptr;
  auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

std::wstring StringArg(const EncodableMap* map, const char* key) {
  const EncodableValue* v = Find(map, key);
  if (!v) return {};
  const auto* s = std::get_if<std::string>(v);
  return s ? ToWide(*s) : std::wstring();
}

const std::vector<uint8_t>* BytesArg(const EncodableMap* map, const char* key) {
  const EncodableValue* v = Find(map, key);
  return v ? std::get_if<std::vector<uint8_t>>(v) : nullptr;
}

Shape ParseShape(const std::string& s) {
  if (s == "circle") return Shape::kCircle;
  if (s == "window") return Shape::kWindow;
  if (s == "screen") return Shape::kScreen;
  return Shape::kRect;
}

const char* ShapeName(Shape s) {
  switch (s) {
    case Shape::kCircle: return "circle";
    case Shape::kWindow: return "window";
    case Shape::kScreen: return "screen";
    default: return "rect";
  }
}

const char* KindName(Kind k) {
  switch (k) {
    case Kind::kVideo: return "video";
    case Kind::kGif: return "gif";
    default: return "image";
  }
}

// ---------------------------------------------------------------- 클립보드

HGLOBAL AllocCopy(const void* data, size_t size) {
  HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!g) return nullptr;
  void* p = GlobalLock(g);
  memcpy(p, data, size);
  GlobalUnlock(g);
  return g;
}

bool OpenClipboardRetry(HWND owner) {
  for (int i = 0; i < 10; ++i) {
    if (OpenClipboard(owner)) return true;
    Sleep(20);
  }
  return false;
}

// 투명한 부분은 흰색 위에 합성한다. CF_DIB 쪽은 알파를 못 쓰는 앱이 많다.
HGLOBAL MakeDib(const Bgra& image) {
  const size_t row = static_cast<size_t>(image.width) * 4;
  const size_t bytes = sizeof(BITMAPINFOHEADER) + row * image.height;
  HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!g) return nullptr;
  auto* base = static_cast<uint8_t*>(GlobalLock(g));
  auto* bih = reinterpret_cast<BITMAPINFOHEADER*>(base);
  *bih = {};
  bih->biSize = sizeof(BITMAPINFOHEADER);
  bih->biWidth = image.width;
  bih->biHeight = image.height;  // 아래에서 위
  bih->biPlanes = 1;
  bih->biBitCount = 32;
  bih->biCompression = BI_RGB;
  bih->biSizeImage = static_cast<DWORD>(row * image.height);
  uint8_t* dst = base + sizeof(BITMAPINFOHEADER);
  for (int y = 0; y < image.height; ++y) {
    const uint8_t* src = image.pixels.data() + static_cast<size_t>(image.height - 1 - y) * row;
    uint8_t* out = dst + static_cast<size_t>(y) * row;
    for (int x = 0; x < image.width; ++x) {
      int a = src[x * 4 + 3];
      for (int c = 0; c < 3; ++c) out[x * 4 + c] = static_cast<uint8_t>((src[x * 4 + c] * a + 255 * (255 - a)) / 255);
      out[x * 4 + 3] = 0xFF;
    }
  }
  GlobalUnlock(g);
  return g;
}

bool CopyImage(HWND owner, const std::vector<uint8_t>& png) {
  Bgra image;
  if (!DecodePng(png, &image)) return false;
  if (!OpenClipboardRetry(owner)) return false;
  EmptyClipboard();
  // "PNG"는 알파를 지키고, CF_DIB는 오래된 앱을 위한 것이다.
  static const UINT png_format = RegisterClipboardFormatW(L"PNG");
  if (HGLOBAL g = AllocCopy(png.data(), png.size())) {
    if (!SetClipboardData(png_format, g)) GlobalFree(g);
  }
  if (HGLOBAL dib = MakeDib(image)) {
    if (!SetClipboardData(CF_DIB, dib)) GlobalFree(dib);
  }
  CloseClipboard();
  return true;
}

bool CopyFileToClipboard(HWND owner, const std::wstring& path) {
  std::wstring list = path;
  list.push_back(L'\0');
  list.push_back(L'\0');
  const size_t bytes = sizeof(DROPFILES) + list.size() * sizeof(wchar_t);
  HGLOBAL g = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes);
  if (!g) return false;
  auto* drop = static_cast<DROPFILES*>(GlobalLock(g));
  drop->pFiles = sizeof(DROPFILES);
  drop->fWide = TRUE;
  memcpy(reinterpret_cast<uint8_t*>(drop) + sizeof(DROPFILES), list.data(), list.size() * sizeof(wchar_t));
  GlobalUnlock(g);

  if (!OpenClipboardRetry(owner)) {
    GlobalFree(g);
    return false;
  }
  EmptyClipboard();
  if (!SetClipboardData(CF_HDROP, g)) GlobalFree(g);
  // GIF는 이미지 영역에 바로 붙여 넣는 앱을 위해 내용도 올린다.
  if (path.size() > 4 && _wcsicmp(path.c_str() + path.size() - 4, L".gif") == 0) {
    FILE* f = nullptr;
    if (_wfopen_s(&f, path.c_str(), L"rb") == 0 && f) {
      std::vector<uint8_t> data;
      uint8_t buf[65536];
      size_t n;
      while ((n = fread(buf, 1, sizeof(buf), f)) > 0) data.insert(data.end(), buf, buf + n);
      fclose(f);
      static const UINT gif_format = RegisterClipboardFormatW(L"GIF");
      if (HGLOBAL gg = AllocCopy(data.data(), data.size())) {
        if (!SetClipboardData(gif_format, gg)) GlobalFree(gg);
      }
    }
  }
  CloseClipboard();
  return true;
}

// ---------------------------------------------------------------- 저장

bool WriteBytes(const std::wstring& path, const std::vector<uint8_t>& data) {
  FILE* f = nullptr;
  if (_wfopen_s(&f, path.c_str(), L"wb") != 0 || !f) return false;
  bool ok = fwrite(data.data(), 1, data.size(), f) == data.size();
  ok = fclose(f) == 0 && ok;
  return ok;
}

// 이미지 폴더에 `Snapdock 2026-10-21 14.03.05.png`로 저장한다.
std::wstring SavePng(const std::vector<uint8_t>& png) {
  std::wstring folder = CaptureConfig::SaveFolder(false);
  if (!EnsureDirectory(folder)) return {};
  std::wstring path = JoinPath(folder, L"Snapdock " + Timestamp() + L".png");
  return WriteBytes(path, png) ? path : std::wstring();
}

// 작업 폴더의 녹화 파일을 저장 폴더로 복사한다. 영상은 영상 폴더, GIF는 이미지 폴더로 간다.
std::wstring SaveRecording(const std::wstring& source) {
  bool gif = source.size() > 4 && _wcsicmp(source.c_str() + source.size() - 4, L".gif") == 0;
  std::wstring folder = CaptureConfig::SaveFolder(!gif);
  if (!EnsureDirectory(folder)) return {};
  size_t slash = source.find_last_of(L"\\/");
  std::wstring name = slash == std::wstring::npos ? source : source.substr(slash + 1);
  std::wstring target = JoinPath(folder, name);
  return CopyFileW(source.c_str(), target.c_str(), FALSE) ? target : std::wstring();
}

void OpenFolder(bool movies) {
  std::wstring folder = CaptureConfig::SaveFolder(movies);
  if (folder.empty()) return;
  EnsureDirectory(folder);
  ShellExecuteW(nullptr, L"open", folder.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

// ---------------------------------------------------------------- 채널

class Handler {
 public:
  explicit Handler(HWND window) : window_(window) {}

  void Handle(const flutter::MethodCall<EncodableValue>& call, std::shared_ptr<Result> result) {
    const std::string& method = call.method_name();
    const EncodableMap* args = Args(call);

    if (method == "permissionStatus" || method == "requestPermission") {
      result->Success(EncodableValue(true));  // Windows에는 화면 기록 권한이 없다
    } else if (method == "openPermissionSettings") {
      result->Success();
    } else if (method == "captureRegion") {
      CaptureRegion(args, std::move(result));
    } else if (method == "stopRecording") {
      StopRecording();
      result->Success();
    } else if (method == "configure") {
      Configure(args);
      result->Success();
    } else if (method == "openFolder") {
      const EncodableValue* kind = Find(args, "kind");
      const auto* s = kind ? std::get_if<std::string>(kind) : nullptr;
      OpenFolder(s && *s == "movies");
      result->Success();
    } else if (method == "copyImage") {
      const auto* png = BytesArg(args, "png");
      if (!png) return result->Error("bad_args", "png is required");
      CopyImage(window_, *png);
      result->Success();
    } else if (method == "copyFile") {
      std::wstring path = StringArg(args, "path");
      if (path.empty()) return result->Error("bad_args", "path is required");
      CopyFileToClipboard(window_, path);
      result->Success();
    } else if (method == "saveImage") {
      const auto* png = BytesArg(args, "png");
      if (!png) return result->Error("bad_args", "png is required");
      ReplyPath(SavePng(*png), *result);
    } else if (method == "saveFile") {
      std::wstring path = StringArg(args, "path");
      if (path.empty()) return result->Error("bad_args", "path is required");
      ReplyPath(SaveRecording(path), *result);
    } else {
      result->NotImplemented();
    }
  }

 private:
  static void ReplyPath(const std::wstring& path, Result& result) {
    if (path.empty()) result.Success();
    else result.Success(EncodableValue(ToUtf8(path)));
  }

  static void Configure(const EncodableMap* args) {
    if (const EncodableValue* v = Find(args, "maxSeconds")) {
      if (const auto* i = std::get_if<int32_t>(v)) CaptureConfig::max_seconds = max(1, static_cast<int>(*i));
    }
    CaptureConfig::image_dir = StringArg(args, "imageDir");
    CaptureConfig::video_dir = StringArg(args, "videoDir");
    CaptureConfig::work_dir = StringArg(args, "workDir");
    CaptureConfig::embed_metadata = false;
    if (const EncodableValue* v = Find(args, "embedMetadata")) {
      if (const auto* b = std::get_if<bool>(v)) CaptureConfig::embed_metadata = *b;
    }
  }

  void CaptureRegion(const EncodableMap* args, std::shared_ptr<Result> result) {
    if (OverlayActive() || RecordingActive()) {
      result->Success();  // 이미 선택·녹화 중이면 무시한다
      return;
    }
    const EncodableValue* shape_value = Find(args, "shape");
    const auto* shape_name = shape_value ? std::get_if<std::string>(shape_value) : nullptr;
    Shape shape = ParseShape(shape_name ? *shape_name : "");

    HWND window = window_;
    bool started = RunOverlay(shape, [window, result](const OverlayResult& r) {
      switch (r.type) {
        case OverlayResult::kCancel:
          result->Success();
          break;
        case OverlayResult::kImage:
          ReplyImage(window, r.image, *result);
          break;
        case OverlayResult::kRecord:
          if (!StartRecording(r.record, [result](const RecordOutcome& o) { ReplyRecording(o, *result); })) {
            result->Error("capture_failed", "could not start recording");
          }
          break;
      }
    });
    if (!started) result->Error("capture_failed", "could not open the capture overlay");
  }

  static void ReplyImage(HWND window, const ImageOutcome& image, Result& result) {
    EncodableMap map;
    map[EncodableValue("action")] = EncodableValue(image.action == Action::kCopy ? "copy" : "save");
    map[EncodableValue("shape")] = EncodableValue(ShapeName(image.shape));
    map[EncodableValue("kind")] = EncodableValue("image");
    map[EncodableValue("png")] = EncodableValue(image.png);
    map[EncodableValue("width")] = EncodableValue(image.width);
    map[EncodableValue("height")] = EncodableValue(image.height);
    if (image.action == Action::kCopy) {
      CopyImage(window, image.png);
    } else {
      std::wstring path = SavePng(image.png);
      if (!path.empty()) map[EncodableValue("path")] = EncodableValue(ToUtf8(path));
    }
    result.Success(EncodableValue(map));
  }

  static void ReplyRecording(const RecordOutcome& o, Result& result) {
    if (!o.ok) {
      result.Error("capture_failed", o.error);
      return;
    }
    EncodableMap map;
    map[EncodableValue("action")] = EncodableValue("copy");
    map[EncodableValue("shape")] = EncodableValue("rect");
    map[EncodableValue("kind")] = EncodableValue(KindName(o.kind));
    map[EncodableValue("png")] = EncodableValue(o.png);
    map[EncodableValue("width")] = EncodableValue(o.width);
    map[EncodableValue("height")] = EncodableValue(o.height);
    map[EncodableValue("path")] = EncodableValue(ToUtf8(o.path));
    map[EncodableValue("durationMs")] = EncodableValue(o.duration_ms);
    result.Success(EncodableValue(map));
  }

  HWND window_;
};

}  // namespace

void RegisterCaptureChannel(flutter::BinaryMessenger* messenger, HWND main_window) {
  StartGdiplus();
  ExcludeFromCapture(main_window);

  static auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "art.zoomon.snapdock/capture", &flutter::StandardMethodCodec::GetInstance());
  static Handler handler(main_window);
  channel->SetMethodCallHandler([](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<Result> result) {
    handler.Handle(call, std::shared_ptr<Result>(std::move(result)));
  });
}

}  // namespace snapdock
