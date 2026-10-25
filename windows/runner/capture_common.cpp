#include "capture_common.h"

#include <knownfolders.h>
#include <shlobj.h>

#include <cstdio>

namespace snapdock {

int CaptureConfig::max_seconds = 10;
std::wstring CaptureConfig::image_dir;
std::wstring CaptureConfig::video_dir;
std::wstring CaptureConfig::work_dir;
bool CaptureConfig::embed_metadata = false;

std::wstring CaptureConfig::SaveFolder(bool movies) {
  const std::wstring& custom = movies ? video_dir : image_dir;
  if (!custom.empty()) return custom;
  PWSTR base = nullptr;
  std::wstring result;
  if (SUCCEEDED(SHGetKnownFolderPath(movies ? FOLDERID_Videos : FOLDERID_Pictures, 0, nullptr, &base))) {
    result = JoinPath(base, L"Snapdock");
  }
  CoTaskMemFree(base);
  return result;
}

std::wstring CaptureConfig::WorkFolder() {
  if (!work_dir.empty()) return work_dir;
  wchar_t temp[MAX_PATH + 1];
  DWORD n = GetTempPathW(MAX_PATH, temp);
  return JoinPath(std::wstring(temp, n), L"Snapdock");
}

namespace {

ULONG_PTR gdiplus_token = 0;

bool FindEncoder(const wchar_t* mime, CLSID* clsid) {
  UINT count = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&count, &size);
  if (size == 0) return false;
  std::vector<uint8_t> buffer(size);
  auto* encoders = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(count, size, encoders);
  for (UINT i = 0; i < count; ++i) {
    if (wcscmp(encoders[i].MimeType, mime) == 0) {
      *clsid = encoders[i].Clsid;
      return true;
    }
  }
  return false;
}

std::vector<uint8_t> SaveBitmapAsPng(Gdiplus::Bitmap& bitmap) {
  CLSID png;
  if (!FindEncoder(L"image/png", &png)) return {};
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return {};
  std::vector<uint8_t> bytes;
  if (bitmap.Save(stream, &png, nullptr) == Gdiplus::Ok) {
    HGLOBAL global = nullptr;
    if (SUCCEEDED(GetHGlobalFromStream(stream, &global))) {
      SIZE_T size = GlobalSize(global);
      // 스트림 길이가 GlobalSize보다 짧을 수 있어 Seek 위치로 잰다.
      LARGE_INTEGER zero = {};
      ULARGE_INTEGER end = {};
      stream->Seek(zero, STREAM_SEEK_CUR, &end);
      if (end.QuadPart > 0 && end.QuadPart <= size) size = static_cast<SIZE_T>(end.QuadPart);
      const void* data = GlobalLock(global);
      if (data) {
        bytes.assign(static_cast<const uint8_t*>(data), static_cast<const uint8_t*>(data) + size);
        GlobalUnlock(global);
      }
    }
  }
  stream->Release();
  return bytes;
}

const char* ShapeName(Shape shape) {
  switch (shape) {
    case Shape::kCircle: return "circle";
    case Shape::kWindow: return "window";
    case Shape::kScreen: return "screen";
    default: return "rect";
  }
}

// GetVersionEx는 매니페스트에 따라 거짓말을 해서 RtlGetVersion을 쓴다.
std::string WindowsVersion() {
  using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  if (HMODULE ntdll = GetModuleHandleW(L"ntdll.dll")) {
    if (auto fn = reinterpret_cast<RtlGetVersionFn>(GetProcAddress(ntdll, "RtlGetVersion"))) fn(&info);
  }
  char buffer[64];
  snprintf(buffer, sizeof(buffer), "Windows %lu.%lu.%lu", info.dwMajorVersion, info.dwMinorVersion, info.dwBuildNumber);
  return buffer;
}

void SetAsciiProperty(Gdiplus::Bitmap& bitmap, PROPID id, const std::string& text) {
  Gdiplus::PropertyItem item = {};
  item.id = id;
  item.type = PropertyTagTypeASCII;
  item.length = static_cast<ULONG>(text.size() + 1);  // 끝의 NUL까지
  item.value = const_cast<char*>(text.c_str());
  bitmap.SetPropertyItem(&item);  // GDI+가 값을 복사해 간다
}

// 스크린샷에 적는 정보. GDI+ PNG 인코더는 Description·Software·DateTime을 텍스트 청크로 쓴다.
void AddScreenshotMetadata(Gdiplus::Bitmap& bitmap, Shape shape) {
  SYSTEMTIME now;
  GetLocalTime(&now);
  char time[32];
  snprintf(time, sizeof(time), "%04d:%02d:%02d %02d:%02d:%02d", now.wYear, now.wMonth, now.wDay, now.wHour,
           now.wMinute, now.wSecond);
  UINT dpi = GetDpiForSystem();
  char description[160];
  snprintf(description, sizeof(description), "Snapdock screenshot (%s, display scale %u%%) on %s", ShapeName(shape),
           dpi * 100 / 96, WindowsVersion().c_str());
  SetAsciiProperty(bitmap, PropertyTagImageDescription, description);
  SetAsciiProperty(bitmap, PropertyTagSoftwareUsed, std::string("Snapdock ") + FLUTTER_VERSION);
  SetAsciiProperty(bitmap, PropertyTagDateTime, time);
  SetAsciiProperty(bitmap, PropertyTagExifDTOrig, time);
}

}  // namespace

void StartGdiplus() {
  if (gdiplus_token) return;
  Gdiplus::GdiplusStartupInput input;
  Gdiplus::GdiplusStartup(&gdiplus_token, &input, nullptr);
}

std::string ToUtf8(const std::wstring& wide) {
  if (wide.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), out.data(), n, nullptr, nullptr);
  return out;
}

std::wstring ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), n);
  return out;
}

std::vector<uint8_t> EncodePng(const Bgra& image) {
  if (image.width <= 0 || image.height <= 0) return {};
  Gdiplus::Bitmap bitmap(image.width, image.height, image.width * 4, PixelFormat32bppARGB,
                         const_cast<uint8_t*>(image.pixels.data()));
  return SaveBitmapAsPng(bitmap);
}

std::vector<uint8_t> EncodeScreenshotPng(const Bgra& image, Shape shape) {
  if (image.width <= 0 || image.height <= 0) return {};
  Gdiplus::Bitmap bitmap(image.width, image.height, image.width * 4, PixelFormat32bppARGB,
                         const_cast<uint8_t*>(image.pixels.data()));
  if (CaptureConfig::embed_metadata) AddScreenshotMetadata(bitmap, shape);
  return SaveBitmapAsPng(bitmap);
}

bool DecodePng(const std::vector<uint8_t>& png, Bgra* out) {
  HGLOBAL global = GlobalAlloc(GMEM_MOVEABLE, png.size());
  if (!global) return false;
  memcpy(GlobalLock(global), png.data(), png.size());
  GlobalUnlock(global);
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(global, TRUE, &stream))) {
    GlobalFree(global);
    return false;
  }
  bool ok = false;
  {
    Gdiplus::Bitmap bitmap(stream);
    if (bitmap.GetLastStatus() == Gdiplus::Ok) {
      int w = static_cast<int>(bitmap.GetWidth()), h = static_cast<int>(bitmap.GetHeight());
      Gdiplus::Rect rect(0, 0, w, h);
      Gdiplus::BitmapData data;
      if (bitmap.LockBits(&rect, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &data) == Gdiplus::Ok) {
        out->width = w;
        out->height = h;
        out->pixels.resize(static_cast<size_t>(w) * h * 4);
        for (int y = 0; y < h; ++y) {
          memcpy(out->pixels.data() + static_cast<size_t>(y) * w * 4,
                 static_cast<const uint8_t*>(data.Scan0) + static_cast<size_t>(y) * data.Stride, static_cast<size_t>(w) * 4);
        }
        bitmap.UnlockBits(&data);
        ok = true;
      }
    }
  }
  stream->Release();
  return ok;
}

std::vector<uint8_t> EncodeThumbnailPng(const Bgra& image, int max_side) {
  if (image.width <= 0 || image.height <= 0) return {};
  int longest = max(image.width, image.height);
  if (longest <= max_side) return EncodePng(image);
  double scale = static_cast<double>(max_side) / longest;
  int w = max(1, static_cast<int>(image.width * scale));
  int h = max(1, static_cast<int>(image.height * scale));
  Gdiplus::Bitmap source(image.width, image.height, image.width * 4, PixelFormat32bppARGB,
                         const_cast<uint8_t*>(image.pixels.data()));
  Gdiplus::Bitmap target(w, h, PixelFormat32bppARGB);
  {
    Gdiplus::Graphics g(&target);
    g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    g.DrawImage(&source, Gdiplus::Rect(0, 0, w, h), 0, 0, image.width, image.height, Gdiplus::UnitPixel);
  }
  return SaveBitmapAsPng(target);
}

std::wstring Timestamp() {
  SYSTEMTIME t;
  GetLocalTime(&t);
  wchar_t buf[32];
  swprintf_s(buf, L"%04d-%02d-%02d %02d.%02d.%02d", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
  return buf;
}

bool EnsureDirectory(const std::wstring& path) {
  if (path.empty()) return false;
  int rc = SHCreateDirectoryExW(nullptr, path.c_str(), nullptr);
  return rc == ERROR_SUCCESS || rc == ERROR_ALREADY_EXISTS || rc == ERROR_FILE_EXISTS;
}

std::wstring JoinPath(const std::wstring& dir, const std::wstring& name) {
  if (dir.empty()) return name;
  wchar_t last = dir.back();
  if (last == L'\\' || last == L'/') return dir + name;
  return dir + L"\\" + name;
}

void ExcludeFromCapture(HWND hwnd) {
  // WDA_EXCLUDEFROMCAPTURE = 0x11. 오래된 SDK에는 상수가 없을 수 있어 값으로 쓴다.
  SetWindowDisplayAffinity(hwnd, 0x11);
}

}  // namespace snapdock
