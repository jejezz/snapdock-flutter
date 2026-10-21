#include "screen_recorder.h"

#include <dwmapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <thread>

// 영역 녹화 (macOS의 ScreenRecorder.swift에 해당한다).
// GDI BitBlt로 영역을 일정 간격으로 떠서 MP4는 Media Foundation H.264, GIF는 직접 만든 인코더로 쓴다.
// 우리 앱 창(독, 알약)은 SetWindowDisplayAffinity로 캡처에서 빠진다.

namespace snapdock {
namespace {

using Microsoft::WRL::ComPtr;
using Clock = std::chrono::steady_clock;

const wchar_t kPillClass[] = L"SnapdockRecordingPill";
constexpr UINT kWmFinished = WM_APP + 1;
constexpr UINT_PTR kPillTimer = 1;

// ---------------------------------------------------------------- MP4

class Mp4Writer {
 public:
  ~Mp4Writer() { Finish(); }

  bool Open(const std::wstring& path, int w, int h, int fps) {
    width_ = w;
    height_ = h;
    if (FAILED(MFCreateSinkWriterFromURL(path.c_str(), nullptr, nullptr, &writer_))) return false;

    UINT32 bitrate = static_cast<UINT32>(min<double>(24e6, max<double>(1.5e6, static_cast<double>(w) * h * fps * 0.14)));
    ComPtr<IMFMediaType> out;
    MFCreateMediaType(&out);
    out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    out->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    out->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
    out->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    MFSetAttributeSize(out.Get(), MF_MT_FRAME_SIZE, w, h);
    MFSetAttributeRatio(out.Get(), MF_MT_FRAME_RATE, fps, 1);
    MFSetAttributeRatio(out.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    if (FAILED(writer_->AddStream(out.Get(), &stream_))) return false;

    ComPtr<IMFMediaType> in;
    MFCreateMediaType(&in);
    in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    in->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    in->SetUINT32(MF_MT_DEFAULT_STRIDE, static_cast<UINT32>(w * 4));  // 양수 = 위에서 아래
    MFSetAttributeSize(in.Get(), MF_MT_FRAME_SIZE, w, h);
    MFSetAttributeRatio(in.Get(), MF_MT_FRAME_RATE, fps, 1);
    MFSetAttributeRatio(in.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    if (FAILED(writer_->SetInputMediaType(stream_, in.Get(), nullptr))) return false;
    if (FAILED(writer_->BeginWriting())) return false;
    open_ = true;
    return true;
  }

  bool Write(const uint32_t* bgra, LONGLONG time_100ns, LONGLONG duration_100ns) {
    if (!open_) return false;
    const DWORD bytes = static_cast<DWORD>(width_) * height_ * 4;
    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(MFCreateMemoryBuffer(bytes, &buffer))) return false;
    BYTE* dst = nullptr;
    if (FAILED(buffer->Lock(&dst, nullptr, nullptr))) return false;
    memcpy(dst, bgra, bytes);
    buffer->Unlock();
    buffer->SetCurrentLength(bytes);
    ComPtr<IMFSample> sample;
    if (FAILED(MFCreateSample(&sample))) return false;
    sample->AddBuffer(buffer.Get());
    sample->SetSampleTime(time_100ns);
    sample->SetSampleDuration(duration_100ns);
    return SUCCEEDED(writer_->WriteSample(stream_, sample.Get()));
  }

  bool Finish() {
    if (!open_) return true;
    open_ = false;
    HRESULT hr = writer_->Finalize();
    writer_.Reset();
    return SUCCEEDED(hr);
  }

 private:
  ComPtr<IMFSinkWriter> writer_;
  DWORD stream_ = 0;
  int width_ = 0, height_ = 0;
  bool open_ = false;
};

// ---------------------------------------------------------------- GIF

// 고정 256색 팔레트(R6 G7 B6 = 252색 + 검정 3 + 투명 1)에 순서 디더링으로 줄이고,
// 앞 프레임과 같은 픽셀은 투명으로 둬서 LZW가 변하지 않은 부분을 거의 공짜로 압축하게 한다.
class GifWriter {
 public:
  ~GifWriter() {
    if (file_) fclose(file_);
  }

  bool Open(const std::wstring& path, int w, int h) {
    if (_wfopen_s(&file_, path.c_str(), L"wb") != 0 || !file_) return false;
    w_ = w;
    h_ = h;
    prev_.assign(static_cast<size_t>(w) * h, 0);
    indices_.resize(static_cast<size_t>(w) * h);
    const uint8_t header[] = {'G', 'I', 'F', '8', '9', 'a'};
    fwrite(header, 1, 6, file_);
    PutU16(w);
    PutU16(h);
    PutByte(0xF7);  // 전역 색상표, 8비트, 256색
    PutByte(0);
    PutByte(0);
    for (int i = 0; i < 256; ++i) {
      uint8_t r = 0, g = 0, b = 0;
      if (i < 252) {
        r = static_cast<uint8_t>((i / 42) * 255 / 5);
        g = static_cast<uint8_t>(((i / 6) % 7) * 255 / 6);
        b = static_cast<uint8_t>((i % 6) * 255 / 5);
      }
      PutByte(r);
      PutByte(g);
      PutByte(b);
    }
    // 반복 확장: 무한 반복.
    const uint8_t loop[] = {0x21, 0xFF, 0x0B, 'N', 'E', 'T', 'S', 'C', 'A', 'P', 'E', '2', '.', '0', 0x03, 0x01, 0x00, 0x00, 0x00};
    fwrite(loop, 1, sizeof(loop), file_);
    return true;
  }

  void AddFrame(const uint32_t* bgra, int delay_cs) {
    static const int kBayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
    const bool first = !has_prev_;
    for (int y = 0; y < h_; ++y) {
      for (int x = 0; x < w_; ++x) {
        uint32_t p = bgra[static_cast<size_t>(y) * w_ + x];
        float bias = ((kBayer[(y & 3) * 4 + (x & 3)] + 0.5f) / 16.0f - 0.5f) * 0.8f;
        int r = Quantize(((p >> 16) & 0xFF) * 5 / 255.0f + bias, 5);
        int g = Quantize(((p >> 8) & 0xFF) * 6 / 255.0f + bias, 6);
        int b = Quantize((p & 0xFF) * 5 / 255.0f + bias, 5);
        size_t i = static_cast<size_t>(y) * w_ + x;
        uint8_t idx = static_cast<uint8_t>((r * 7 + g) * 6 + b);
        uint8_t out = (!first && idx == prev_[i]) ? 255 : idx;
        prev_[i] = idx;
        indices_[i] = out;
      }
    }
    has_prev_ = true;

    // 그래픽 제어 확장: 처리 방식 1(그대로 둠), 투명 색 255.
    PutByte(0x21);
    PutByte(0xF9);
    PutByte(4);
    PutByte(static_cast<uint8_t>((1 << 2) | (first ? 0 : 1)));
    PutU16(delay_cs);
    PutByte(255);
    PutByte(0);
    // 이미지 설명자.
    PutByte(0x2C);
    PutU16(0);
    PutU16(0);
    PutU16(w_);
    PutU16(h_);
    PutByte(0);
    PutByte(8);  // LZW 최소 코드 크기
    std::vector<uint8_t> data;
    Lzw(indices_, &data);
    for (size_t off = 0; off < data.size(); off += 255) {
      size_t n = min<size_t>(255, data.size() - off);
      PutByte(static_cast<uint8_t>(n));
      fwrite(data.data() + off, 1, n, file_);
    }
    PutByte(0);
  }

  bool Finish() {
    if (!file_) return false;
    PutByte(0x3B);
    bool ok = fflush(file_) == 0;
    fclose(file_);
    file_ = nullptr;
    return ok;
  }

 private:
  static int Quantize(float v, int max_level) { return max(0, min(max_level, static_cast<int>(v + 0.5f))); }
  void PutByte(uint8_t b) { fputc(b, file_); }
  void PutU16(int v) {
    PutByte(static_cast<uint8_t>(v & 0xFF));
    PutByte(static_cast<uint8_t>((v >> 8) & 0xFF));
  }

  static void Lzw(const std::vector<uint8_t>& px, std::vector<uint8_t>* out) {
    constexpr int kClear = 256, kEnd = 257;
    uint16_t child[4096], sibling[4096];
    uint8_t ch[4096];
    int code_size = 9, next = 258;
    uint32_t bitbuf = 0;
    int nbits = 0;
    auto emit = [&](int code) {
      bitbuf |= static_cast<uint32_t>(code) << nbits;
      nbits += code_size;
      while (nbits >= 8) {
        out->push_back(static_cast<uint8_t>(bitbuf & 0xFF));
        bitbuf >>= 8;
        nbits -= 8;
      }
    };
    auto reset = [&]() {
      memset(child, 0, sizeof(child));
      memset(sibling, 0, sizeof(sibling));
      code_size = 9;
      next = 258;
    };
    reset();
    emit(kClear);
    int prefix = px[0];
    for (size_t i = 1; i < px.size(); ++i) {
      uint8_t c = px[i];
      int found = 0;
      for (int k = child[prefix]; k; k = sibling[k]) {
        if (ch[k] == c) {
          found = k;
          break;
        }
      }
      if (found) {
        prefix = found;
        continue;
      }
      emit(prefix);
      if (next < 4096) {
        ch[next] = c;
        sibling[next] = child[prefix];
        child[prefix] = static_cast<uint16_t>(next);
        ++next;
        if (next == (1 << code_size) + 1 && code_size < 12) ++code_size;
      } else {
        emit(kClear);
        reset();
      }
      prefix = c;
    }
    emit(prefix);
    emit(kEnd);
    if (nbits > 0) out->push_back(static_cast<uint8_t>(bitbuf & 0xFF));
  }

  FILE* file_ = nullptr;
  int w_ = 0, h_ = 0;
  bool has_prev_ = false;
  std::vector<uint8_t> prev_;
  std::vector<uint8_t> indices_;
};

// ---------------------------------------------------------------- 녹화기

HBITMAP CreateDib(HDC dc, int w, int h, uint32_t** bits) {
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  return CreateDIBSection(dc, &bi, DIB_RGB_COLORS, reinterpret_cast<void**>(bits), nullptr, 0);
}

class Recorder {
 public:
  bool Start(const RecordRequest& request, RecordCallback callback);
  void RequestStop() { stop_ = true; }

 private:
  static LRESULT CALLBACK PillProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  LRESULT OnPill(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  void CreatePill();
  void PaintPill(HDC dc);
  void Run();
  void Complete();
  int S(double v) const { return static_cast<int>(std::lround(v * scale_)); }

  RecordRequest request_;
  RecordCallback callback_;
  RecordOutcome outcome_;
  std::thread thread_;
  std::atomic<bool> stop_{false};
  HWND pill_ = nullptr;
  double scale_ = 1.0;
  int width_ = 0, height_ = 0;
  Clock::time_point started_;
  RECT stop_button_ = {};
  RECT pill_rect_ = {};
};

Recorder* g_recorder = nullptr;

bool Recorder::Start(const RecordRequest& request, RecordCallback callback) {
  request_ = request;
  callback_ = std::move(callback);
  width_ = request.region.right - request.region.left;
  height_ = request.region.bottom - request.region.top;
  if (request.kind == Kind::kVideo) {
    width_ &= ~1;  // H.264는 짝수 크기가 필요하다
    height_ &= ~1;
  }
  if (width_ < 16 || height_ < 16) return false;
  outcome_.kind = request.kind;
  outcome_.width = width_;
  outcome_.height = height_;
  started_ = Clock::now();
  CreatePill();
  thread_ = std::thread([this] { Run(); });
  return true;
}

// 녹화 스레드. 끝나면 알약 창에 알린다.
void Recorder::Run() {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool gif = request_.kind == Kind::kGif;
  const bool video = !gif;
  bool mf = false;
  Sleep(150);  // 오버레이가 화면에서 사라질 시간

  HDC screen = GetDC(nullptr);
  HDC cap_dc = CreateCompatibleDC(screen);
  uint32_t* cap_bits = nullptr;
  HBITMAP cap_bmp = CreateDib(screen, width_, height_, &cap_bits);
  HGDIOBJ cap_old = cap_bmp ? SelectObject(cap_dc, cap_bmp) : nullptr;

  int gw = min(width_, kGifMaxWidth);
  int gh = max(1, static_cast<int>(std::lround(static_cast<double>(height_) * gw / width_)));
  HDC gif_dc = nullptr;
  HBITMAP gif_bmp = nullptr;
  HGDIOBJ gif_old = nullptr;
  uint32_t* gif_bits = nullptr;
  if (gif) {
    gif_dc = CreateCompatibleDC(screen);
    gif_bmp = CreateDib(screen, gw, gh, &gif_bits);
    if (gif_bmp) gif_old = SelectObject(gif_dc, gif_bmp);
    SetStretchBltMode(gif_dc, HALFTONE);
    SetBrushOrgEx(gif_dc, 0, 0, nullptr);
  }

  const std::wstring folder = CaptureConfig::WorkFolder();
  EnsureDirectory(folder);
  const std::wstring path = JoinPath(folder, L"Snapdock " + Timestamp() + (gif ? L".gif" : L".mp4"));

  Mp4Writer mp4;
  GifWriter gifw;
  bool ready = cap_bmp && (!gif || gif_bmp);
  if (ready && video) {
    mf = SUCCEEDED(MFStartup(MF_VERSION));
    ready = mf && mp4.Open(path, width_, height_, kVideoFps);
    if (!ready) outcome_.error = "could not start the H.264 encoder";
  } else if (ready) {
    ready = gifw.Open(path, gw, gh);
    if (!ready) outcome_.error = "could not create the GIF file";
  } else {
    outcome_.error = "could not allocate capture buffers";
  }

  int origin_x = request_.region.left, origin_y = request_.region.top;
  const int fps = gif ? kGifFps : kVideoFps;
  const int interval_ms = 1000 / fps;
  const LONGLONG max_ms = static_cast<LONGLONG>(CaptureConfig::max_seconds) * 1000;
  int frames = 0;
  LONGLONG last_time = -1;
  LONGLONG elapsed_ms = 0;
  Bgra first_frame;
  bool write_failed = false;

  if (ready) {
    const auto t0 = Clock::now();
    while (!stop_) {
      elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0).count();
      if (elapsed_ms >= max_ms) {
        elapsed_ms = max_ms;
        break;
      }
      if (request_.window) {
        RECT fb;
        if (SUCCEEDED(DwmGetWindowAttribute(request_.window, DWMWA_EXTENDED_FRAME_BOUNDS, &fb, sizeof(fb)))) {
          origin_x = fb.left;
          origin_y = fb.top;
        }
      }
      BitBlt(cap_dc, 0, 0, width_, height_, screen, origin_x, origin_y, SRCCOPY | CAPTUREBLT);
      CURSORINFO ci = {sizeof(ci)};
      if (GetCursorInfo(&ci) && (ci.flags & CURSOR_SHOWING)) {
        ICONINFO ii = {};
        if (GetIconInfo(ci.hCursor, &ii)) {
          DrawIconEx(cap_dc, ci.ptScreenPos.x - ii.xHotspot - origin_x, ci.ptScreenPos.y - ii.yHotspot - origin_y,
                     ci.hCursor, 0, 0, 0, nullptr, DI_NORMAL);
          if (ii.hbmMask) DeleteObject(ii.hbmMask);
          if (ii.hbmColor) DeleteObject(ii.hbmColor);
        }
      }
      GdiFlush();
      for (size_t i = 0, n = static_cast<size_t>(width_) * height_; i < n && frames == 0; ++i) cap_bits[i] |= 0xFF000000u;
      if (frames == 0) {
        first_frame.width = width_;
        first_frame.height = height_;
        first_frame.pixels.assign(reinterpret_cast<uint8_t*>(cap_bits), reinterpret_cast<uint8_t*>(cap_bits) + static_cast<size_t>(width_) * height_ * 4);
      }
      if (gif) {
        StretchBlt(gif_dc, 0, 0, gw, gh, cap_dc, 0, 0, width_, height_, SRCCOPY);
        GdiFlush();
        gifw.AddFrame(gif_bits, interval_ms / 10);
      } else {
        LONGLONG t = elapsed_ms * 10000;
        if (t <= last_time) t = last_time + 1;
        last_time = t;
        if (!mp4.Write(cap_bits, t, 10000000LL / fps)) {
          write_failed = true;
          break;
        }
      }
      ++frames;
      // 다음 프레임 시각까지 잔다. 밀렸으면 건너뛴다.
      LONGLONG target = static_cast<LONGLONG>(frames) * interval_ms;
      for (;;) {
        LONGLONG now = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0).count();
        if (stop_ || now >= target || now >= max_ms) break;
        Sleep(static_cast<DWORD>(min<LONGLONG>(target - now, 10)));
      }
    }
    if (elapsed_ms == 0) {
      elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0).count();
    } else if (stop_) {
      elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0).count();
    }
    elapsed_ms = min(elapsed_ms, max_ms);
  }

  bool finished = false;
  if (ready) finished = gif ? gifw.Finish() : mp4.Finish();
  if (mf) MFShutdown();

  if (gif_dc) {
    if (gif_old) SelectObject(gif_dc, gif_old);
    DeleteDC(gif_dc);
  }
  if (gif_bmp) DeleteObject(gif_bmp);
  if (cap_dc) {
    if (cap_old) SelectObject(cap_dc, cap_old);
    DeleteDC(cap_dc);
  }
  if (cap_bmp) DeleteObject(cap_bmp);
  ReleaseDC(nullptr, screen);

  if (ready && frames > 0 && finished && !write_failed) {
    outcome_.ok = true;
    outcome_.path = path;
    outcome_.duration_ms = static_cast<int>(max<LONGLONG>(elapsed_ms, frames * interval_ms));
    outcome_.png = EncodeThumbnailPng(first_frame, 640);
    if (gif) {
      outcome_.width = gw;
      outcome_.height = gh;
    }
  } else {
    if (outcome_.error.empty()) outcome_.error = write_failed ? "could not write a video frame" : "no frames were recorded";
    DeleteFileW(path.c_str());
  }
  CoUninitialize();
  PostMessageW(pill_, kWmFinished, 0, 0);
}

void Recorder::Complete() {
  if (thread_.joinable()) thread_.join();
  KillTimer(pill_, kPillTimer);
  DestroyWindow(pill_);
  pill_ = nullptr;
  RecordOutcome outcome = std::move(outcome_);
  RecordCallback callback = std::move(callback_);
  Recorder* self = this;
  g_recorder = nullptr;
  delete self;
  if (callback) callback(outcome);
}

// ---------------------------------------------------------------- 알약

void Recorder::CreatePill() {
  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = PillProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kPillClass;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassW(&wc);
    registered = true;
  }
  HMONITOR monitor = MonitorFromRect(&request_.region, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {sizeof(mi)};
  GetMonitorInfoW(monitor, &mi);
  pill_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kPillClass, L"Snapdock Recording", WS_POPUP, 0, 0,
                          100, 40, nullptr, nullptr, GetModuleHandleW(nullptr), this);
  scale_ = GetDpiForWindow(pill_) / 96.0;
  const int w = S(210), h = S(40);
  const int x = (mi.rcMonitor.left + mi.rcMonitor.right) / 2 - w / 2;
  const int y = mi.rcMonitor.top + S(12);
  SetWindowPos(pill_, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
  HRGN rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, h, h);
  SetWindowRgn(pill_, rgn, TRUE);
  ExcludeFromCapture(pill_);
  pill_rect_ = {0, 0, w, h};
  stop_button_ = {w - S(34), S(6), w - S(6), h - S(6)};
  SetTimer(pill_, kPillTimer, 100, nullptr);
  ShowWindow(pill_, SW_SHOWNOACTIVATE);
}

std::wstring Clock2(int seconds) {
  wchar_t buf[16];
  swprintf_s(buf, L"%02d:%02d", seconds / 60, seconds % 60);
  return buf;
}

void Recorder::PaintPill(HDC target) {
  const int w = pill_rect_.right, h = pill_rect_.bottom;
  HDC dc = CreateCompatibleDC(target);
  HBITMAP bmp = CreateCompatibleBitmap(target, w, h);
  HGDIOBJ old = SelectObject(dc, bmp);
  {
    Gdiplus::Graphics g(dc);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
    Gdiplus::SolidBrush bg(Gdiplus::Color(255, 34, 34, 38));
    g.FillRectangle(&bg, 0, 0, w, h);

    auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started_).count();
    int elapsed = static_cast<int>(min<long long>(elapsed_ms / 1000, CaptureConfig::max_seconds));
    // 깜빡이는 빨간 점.
    if ((elapsed_ms / 500) % 2 == 0) {
      Gdiplus::SolidBrush red(Gdiplus::Color(255, 255, 59, 48));
      g.FillEllipse(&red, static_cast<float>(S(16)), h / 2.0f - S(5), static_cast<float>(S(10)), static_cast<float>(S(10)));
    }
    std::wstring text = Clock2(elapsed) + L" / " + Clock2(CaptureConfig::max_seconds);
    Gdiplus::FontFamily family(L"Segoe UI");
    Gdiplus::Font font(&family, static_cast<Gdiplus::REAL>(S(14)), Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush fg(Gdiplus::Color(255, 255, 255, 255));
    Gdiplus::StringFormat fmt;
    fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    g.DrawString(text.c_str(), -1, &font, Gdiplus::RectF(static_cast<float>(S(34)), 0, static_cast<float>(S(130)), static_cast<float>(h)), &fmt, &fg);

    // 정지 단추: 흰 원 안의 사각형.
    Gdiplus::SolidBrush circle(Gdiplus::Color(255, 70, 70, 76));
    g.FillEllipse(&circle, static_cast<float>(stop_button_.left), static_cast<float>(stop_button_.top),
                  static_cast<float>(stop_button_.right - stop_button_.left), static_cast<float>(stop_button_.bottom - stop_button_.top));
    float cx = (stop_button_.left + stop_button_.right) / 2.0f, cy = (stop_button_.top + stop_button_.bottom) / 2.0f;
    g.FillRectangle(&fg, cx - S(5), cy - S(5), static_cast<float>(S(10)), static_cast<float>(S(10)));
  }
  BitBlt(target, 0, 0, w, h, dc, 0, 0, SRCCOPY);
  SelectObject(dc, old);
  DeleteObject(bmp);
  DeleteDC(dc);
}

LRESULT CALLBACK Recorder::PillProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
  }
  auto* self = reinterpret_cast<Recorder*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (!self || self != g_recorder || !self->pill_) return DefWindowProcW(hwnd, msg, wp, lp);
  return self->OnPill(hwnd, msg, wp, lp);
}

LRESULT Recorder::OnPill(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      PaintPill(dc);
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_TIMER:
      if (wp == kPillTimer) InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_LBUTTONDOWN: {
      POINT p = {static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp))};
      if (PtInRect(&stop_button_, p)) stop_ = true;
      return 0;
    }
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case kWmFinished:
      Complete();  // this가 지워진다
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

}  // namespace

bool StartRecording(const RecordRequest& request, RecordCallback callback) {
  if (g_recorder) return false;
  g_recorder = new Recorder();
  if (!g_recorder->Start(request, std::move(callback))) {
    delete g_recorder;
    g_recorder = nullptr;
    return false;
  }
  return true;
}

void StopRecording() {
  if (g_recorder) g_recorder->RequestStop();
}

bool RecordingActive() { return g_recorder != nullptr; }

}  // namespace snapdock
