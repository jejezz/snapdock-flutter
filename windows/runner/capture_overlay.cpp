#include "capture_overlay.h"

#include <dwmapi.h>

#include <cmath>
#include <cstdio>

// 영역 선택 오버레이 (macOS의 CaptureOverlay.swift에 해당한다).
// 커서가 있는 모니터를 GDI로 얼린 그림 위에 전체 화면 창을 띄우고, 거기서 영역·창을 고른다.
// 이 프로세스는 PerMonitorV2 DPI 인식이라 모든 좌표가 물리 픽셀이다.

namespace snapdock {
namespace {

using Gdiplus::Color;
using Gdiplus::Graphics;
using Gdiplus::Pen;
using Gdiplus::SolidBrush;

const wchar_t kClassName[] = L"SnapdockCaptureOverlay";
constexpr UINT_PTR kFlashTimer = 1;
constexpr DWORD kFlashMs = 160;

enum Btn { kBtnRect, kBtnCircle, kBtnWindow, kBtnScreen, kBtnVideo, kBtnGif, kBtnCopy, kBtnSave, kBtnClose, kBtnSep };

struct Button {
  Btn id;
  RECT rect;
};

struct WinTarget {
  HWND hwnd;
  RECT rect;  // 오버레이 좌표 (창의 보이는 테두리)
  std::wstring title;
};

struct Handle {
  int dx = 0;
  int dy = 0;
  bool valid() const { return dx != 0 || dy != 0; }
};

int Width(const RECT& r) { return r.right - r.left; }
int Height(const RECT& r) { return r.bottom - r.top; }
bool Contains(const RECT& r, int x, int y) { return x >= r.left && x < r.right && y >= r.top && y < r.bottom; }

RECT Normalized(int x0, int y0, int x1, int y1) {
  return {min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)};
}

HBITMAP CreateDib(HDC dc, int w, int h, uint32_t** bits) {
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;  // 위에서 아래
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  return CreateDIBSection(dc, &bi, DIB_RGB_COLORS, reinterpret_cast<void**>(bits), nullptr, 0);
}

class Overlay {
 public:
  bool Start(Shape initial, OverlayCallback callback);

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  LRESULT OnMessage(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

  int S(double v) const { return static_cast<int>(std::lround(v * scale_)); }

  void EnumerateWindows();
  const WinTarget* WindowAt(int x, int y) const;
  bool Freeze();
  void Release();

  RECT CurrentRect() const;  // 지금 보여 줄 영역 (창 모드에서는 hover 창)
  bool HasSelection() const { return has_sel_ && Width(sel_) > 0 && Height(sel_) > 0; }
  Handle HitHandle(int x, int y) const;
  void SetShape(Shape s);
  void LayoutToolbar();
  Btn HitButton(int x, int y) const;

  void OnMouseDown(int x, int y);
  void OnMouseMove(int x, int y);
  void OnMouseUp(int x, int y);
  void OnButton(Btn id);
  void UpdateCursor(int x, int y);

  void Paint(HDC target);
  void DrawToolbar(Graphics& g);
  void DrawIcon(Graphics& g, Btn id, const RECT& r);

  Bgra Crop(RECT r) const;
  bool RenderWindow(const WinTarget& t, Bgra* out) const;
  std::vector<uint8_t> RenderPng(Bgra* image, bool circle) const;
  void Confirm(Action action);
  void StartRecording(Kind kind);
  void ChooseScreen();
  void Finish(OverlayResult result, bool flash, RECT flash_rect, bool flash_circle);
  void Close();

  OverlayCallback callback_;
  OverlayResult result_;
  HWND hwnd_ = nullptr;
  RECT mon_ = {};
  int w_ = 0, h_ = 0;
  double scale_ = 1.0;

  HDC frozen_dc_ = nullptr, dim_dc_ = nullptr, back_dc_ = nullptr;
  HBITMAP frozen_bmp_ = nullptr, dim_bmp_ = nullptr, back_bmp_ = nullptr;
  HGDIOBJ frozen_old_ = nullptr, dim_old_ = nullptr, back_old_ = nullptr;
  uint32_t* frozen_bits_ = nullptr;
  uint32_t* dim_bits_ = nullptr;

  std::vector<WinTarget> windows_;
  const WinTarget* hovered_ = nullptr;
  const WinTarget* locked_ = nullptr;

  Shape shape_ = Shape::kRect;
  RECT sel_ = {};
  bool has_sel_ = false;

  enum class Drag { kNone, kCreating, kMoving, kResizing } drag_ = Drag::kNone;
  POINT drag_start_ = {};
  RECT drag_original_ = {};
  snapdock::Handle drag_handle_;

  std::vector<Button> buttons_;
  RECT bar_ = {};
  bool bar_visible_ = false;
  Btn hot_button_ = kBtnSep;

  bool finishing_ = false;
  RECT flash_rect_ = {};
  bool flash_circle_ = false;
  DWORD flash_start_ = 0;
  HCURSOR cursor_ = nullptr;
};

Overlay* g_overlay = nullptr;

// ---------------------------------------------------------------- 시작과 정리

bool Overlay::Start(Shape initial, OverlayCallback callback) {
  callback_ = std::move(callback);
  shape_ = (initial == Shape::kScreen) ? Shape::kRect : initial;

  POINT cursor;
  GetCursorPos(&cursor);
  HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {sizeof(mi)};
  if (!GetMonitorInfoW(monitor, &mi)) return false;
  mon_ = mi.rcMonitor;
  w_ = Width(mon_);
  h_ = Height(mon_);

  EnumerateWindows();
  if (!Freeze()) {
    Release();
    return false;
  }

  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kClassName;
    wc.hCursor = LoadCursorW(nullptr, IDC_CROSS);
    RegisterClassW(&wc);
    registered = true;
  }
  hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName, L"Snapdock", WS_POPUP, mon_.left, mon_.top, w_,
                          h_, nullptr, nullptr, GetModuleHandleW(nullptr), this);
  if (!hwnd_) {
    Release();
    return false;
  }
  scale_ = GetDpiForWindow(hwnd_) / 96.0;
  cursor_ = LoadCursorW(nullptr, IDC_CROSS);

  if (shape_ == Shape::kWindow) hovered_ = WindowAt(cursor.x - mon_.left, cursor.y - mon_.top);
  bar_visible_ = true;
  LayoutToolbar();

  ShowWindow(hwnd_, SW_SHOW);
  // 단축키로 불렸을 때 앞으로 나오지 못하는 경우가 있어 Alt 키 입력으로 전경 권한을 얻는다.
  keybd_event(VK_MENU, 0, 0, 0);
  keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
  SetForegroundWindow(hwnd_);
  SetFocus(hwnd_);
  InvalidateRect(hwnd_, nullptr, FALSE);
  return true;
}

bool Overlay::Freeze() {
  HDC screen = GetDC(nullptr);
  frozen_dc_ = CreateCompatibleDC(screen);
  dim_dc_ = CreateCompatibleDC(screen);
  back_dc_ = CreateCompatibleDC(screen);
  frozen_bmp_ = CreateDib(screen, w_, h_, &frozen_bits_);
  dim_bmp_ = CreateDib(screen, w_, h_, &dim_bits_);
  back_bmp_ = CreateCompatibleBitmap(screen, w_, h_);
  bool ok = frozen_dc_ && dim_dc_ && back_dc_ && frozen_bmp_ && dim_bmp_ && back_bmp_;
  if (ok) {
    frozen_old_ = SelectObject(frozen_dc_, frozen_bmp_);
    dim_old_ = SelectObject(dim_dc_, dim_bmp_);
    back_old_ = SelectObject(back_dc_, back_bmp_);
    ok = BitBlt(frozen_dc_, 0, 0, w_, h_, screen, mon_.left, mon_.top, SRCCOPY | CAPTUREBLT) != FALSE;
  }
  ReleaseDC(nullptr, screen);
  if (!ok) return false;
  // 바깥 45% 어둡게: 밝기를 55%로.
  size_t count = static_cast<size_t>(w_) * h_;
  for (size_t i = 0; i < count; ++i) {
    uint32_t p = frozen_bits_[i];
    uint32_t r = (((p >> 16) & 0xFF) * 141) >> 8;
    uint32_t g = (((p >> 8) & 0xFF) * 141) >> 8;
    uint32_t b = ((p & 0xFF) * 141) >> 8;
    dim_bits_[i] = 0xFF000000u | (r << 16) | (g << 8) | b;
  }
  return true;
}

void Overlay::Release() {
  if (frozen_dc_) {
    if (frozen_old_) SelectObject(frozen_dc_, frozen_old_);
    DeleteDC(frozen_dc_);
  }
  if (dim_dc_) {
    if (dim_old_) SelectObject(dim_dc_, dim_old_);
    DeleteDC(dim_dc_);
  }
  if (back_dc_) {
    if (back_old_) SelectObject(back_dc_, back_old_);
    DeleteDC(back_dc_);
  }
  if (frozen_bmp_) DeleteObject(frozen_bmp_);
  if (dim_bmp_) DeleteObject(dim_bmp_);
  if (back_bmp_) DeleteObject(back_bmp_);
  frozen_dc_ = dim_dc_ = back_dc_ = nullptr;
  frozen_bmp_ = dim_bmp_ = back_bmp_ = nullptr;
  frozen_old_ = dim_old_ = back_old_ = nullptr;
}

void Overlay::Close() {
  OverlayResult result = std::move(result_);
  OverlayCallback callback = std::move(callback_);
  if (hwnd_) {
    HWND h = hwnd_;
    hwnd_ = nullptr;
    DestroyWindow(h);
  }
  Release();
  Overlay* self = this;
  g_overlay = nullptr;
  delete self;  // 아래에서 멤버를 쓰지 않는다
  if (callback) callback(result);
}

// ---------------------------------------------------------------- 창 목록

BOOL CALLBACK EnumProc(HWND hwnd, LPARAM lp) {
  auto* list = reinterpret_cast<std::vector<HWND>*>(lp);
  list->push_back(hwnd);
  return TRUE;
}

void Overlay::EnumerateWindows() {
  std::vector<HWND> all;
  EnumWindows(EnumProc, reinterpret_cast<LPARAM>(&all));  // Z 순서, 앞에서부터
  DWORD own = GetCurrentProcessId();
  for (HWND hwnd : all) {
    if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) continue;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == own) continue;
    BOOL cloaked = FALSE;
    DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
    if (cloaked) continue;
    wchar_t cls[64] = {};
    GetClassNameW(hwnd, cls, 64);
    if (wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0) continue;
    wchar_t title[256] = {};
    GetWindowTextW(hwnd, title, 256);
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    bool taskbar = wcscmp(cls, L"Shell_TrayWnd") == 0 || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0;
    if (!taskbar && title[0] == 0 && (ex & (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW))) continue;
    if (!taskbar && (ex & WS_EX_TRANSPARENT) && (ex & WS_EX_LAYERED) && title[0] == 0) continue;

    RECT r;
    if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &r, sizeof(r)))) {
      if (!GetWindowRect(hwnd, &r)) continue;
    }
    RECT local = {r.left - mon_.left, r.top - mon_.top, r.right - mon_.left, r.bottom - mon_.top};
    RECT clipped = {max(local.left, 0L), max(local.top, 0L), min(local.right, static_cast<LONG>(w_)),
                    min(local.bottom, static_cast<LONG>(h_))};
    if (Width(clipped) < 20 || Height(clipped) < 20) continue;
    windows_.push_back({hwnd, local, title});
  }
}

const WinTarget* Overlay::WindowAt(int x, int y) const {
  for (const auto& t : windows_) {
    if (Contains(t.rect, x, y)) return &t;
  }
  return nullptr;
}

// ---------------------------------------------------------------- 상태

RECT Overlay::CurrentRect() const {
  RECT r = {};
  if (shape_ == Shape::kWindow) {
    if (locked_) r = locked_->rect;
    else if (hovered_) r = hovered_->rect;
    else return {};
  } else if (HasSelection()) {
    r = sel_;
  } else {
    return {};
  }
  r.left = max(r.left, 0L);
  r.top = max(r.top, 0L);
  r.right = min(r.right, static_cast<LONG>(w_));
  r.bottom = min(r.bottom, static_cast<LONG>(h_));
  return r;
}

Handle Overlay::HitHandle(int x, int y) const {
  if (!HasSelection() || shape_ == Shape::kWindow) return {};
  const int tol = S(9);
  for (int dy = -1; dy <= 1; ++dy) {
    for (int dx = -1; dx <= 1; ++dx) {
      if (dx == 0 && dy == 0) continue;
      int px = dx < 0 ? sel_.left : dx > 0 ? sel_.right : (sel_.left + sel_.right) / 2;
      int py = dy < 0 ? sel_.top : dy > 0 ? sel_.bottom : (sel_.top + sel_.bottom) / 2;
      if (std::abs(x - px) <= tol && std::abs(y - py) <= tol) {
        Handle h;
        h.dx = dx;
        h.dy = dy;
        return h;
      }
    }
  }
  return {};
}

void Overlay::SetShape(Shape s) {
  if (shape_ == s) return;
  RECT current = CurrentRect();
  shape_ = s;
  if (s == Shape::kWindow) {
    has_sel_ = false;
    locked_ = nullptr;
    POINT p;
    GetCursorPos(&p);
    hovered_ = WindowAt(p.x - mon_.left, p.y - mon_.top);
  } else if (locked_) {
    // 고정한 창의 영역을 그대로 가져와 사각형/원형으로 다듬을 수 있게 한다.
    sel_ = current;
    has_sel_ = true;
    locked_ = nullptr;
    hovered_ = nullptr;
  }
  LayoutToolbar();
  InvalidateRect(hwnd_, nullptr, FALSE);
}

// ---------------------------------------------------------------- 툴바

void Overlay::LayoutToolbar() {
  buttons_.clear();
  std::vector<Btn> order = {kBtnRect, kBtnCircle, kBtnWindow, kBtnScreen};
  bool selection = (shape_ == Shape::kWindow) ? locked_ != nullptr : HasSelection();
  if (selection) {
    order.insert(order.end(), {kBtnSep, kBtnVideo, kBtnGif, kBtnSep, kBtnCopy, kBtnSave});
  }
  order.insert(order.end(), {kBtnSep, kBtnClose});

  const int bw = S(36), bh = S(32), pad = S(4), sep = S(9), gap = S(2);
  int total = pad * 2;
  for (Btn b : order) total += (b == kBtnSep ? sep : bw) + gap;
  total -= gap;
  int height = bh + pad * 2;

  int x, y;
  if (selection) {
    RECT r = CurrentRect();
    x = (r.left + r.right) / 2 - total / 2;
    y = r.bottom + S(12);
    if (y + height > h_ - S(8)) y = r.top - height - S(12);
    if (y < S(8)) y = h_ - height - S(24);  // 위아래 모두 공간이 없으면 영역 안쪽 아래
  } else {
    x = w_ / 2 - total / 2;
    y = h_ - height - S(64);
  }
  x = max(S(8), min(x, w_ - total - S(8)));
  bar_ = {x, y, x + total, y + height};

  int cx = x + pad;
  for (Btn b : order) {
    int width = (b == kBtnSep) ? sep : bw;
    buttons_.push_back({b, {cx, y + pad, cx + width, y + pad + bh}});
    cx += width + gap;
  }
}

Btn Overlay::HitButton(int x, int y) const {
  if (!bar_visible_) return kBtnSep;
  for (const auto& b : buttons_) {
    if (b.id != kBtnSep && Contains(b.rect, x, y)) return b.id;
  }
  return kBtnSep;
}

// ---------------------------------------------------------------- 입력

void Overlay::UpdateCursor(int x, int y) {
  LPCWSTR id = IDC_CROSS;
  if (HitButton(x, y) != kBtnSep || (bar_visible_ && Contains(bar_, x, y))) {
    id = IDC_ARROW;
  } else if (shape_ == Shape::kWindow) {
    id = IDC_ARROW;
  } else if (drag_ == Drag::kMoving) {
    id = IDC_SIZEALL;
  } else {
    Handle h = drag_ == Drag::kResizing ? drag_handle_ : HitHandle(x, y);
    if (h.valid()) {
      if (h.dx == 0) id = IDC_SIZENS;
      else if (h.dy == 0) id = IDC_SIZEWE;
      else if (h.dx == h.dy) id = IDC_SIZENWSE;
      else id = IDC_SIZENESW;
    } else if (HasSelection() && Contains(sel_, x, y)) {
      id = IDC_SIZEALL;
    }
  }
  cursor_ = LoadCursorW(nullptr, id);
  SetCursor(cursor_);
}

void Overlay::OnMouseDown(int x, int y) {
  Btn hit = HitButton(x, y);
  if (hit != kBtnSep) {
    OnButton(hit);
    return;
  }
  if (bar_visible_ && Contains(bar_, x, y)) return;

  if (shape_ == Shape::kWindow) {
    const WinTarget* target = WindowAt(x, y);
    if (target && (!locked_ || !Contains(locked_->rect, x, y))) {
      locked_ = target;
      hovered_ = target;
    } else if (locked_ && !Contains(locked_->rect, x, y)) {
      locked_ = nullptr;
    }
    bar_visible_ = true;
    LayoutToolbar();
    InvalidateRect(hwnd_, nullptr, FALSE);
    return;
  }

  bar_visible_ = false;
  Handle h = HitHandle(x, y);
  if (h.valid()) {
    drag_ = Drag::kResizing;
    drag_handle_ = h;
    drag_original_ = sel_;
  } else if (HasSelection() && Contains(sel_, x, y)) {
    drag_ = Drag::kMoving;
    drag_start_ = {x, y};
    drag_original_ = sel_;
  } else {
    has_sel_ = false;
    drag_ = Drag::kCreating;
    drag_start_ = {x, y};
  }
  SetCapture(hwnd_);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void Overlay::OnMouseMove(int x, int y) {
  if (finishing_) return;
  if (shape_ == Shape::kWindow) {
    const WinTarget* target = WindowAt(x, y);
    if (target != hovered_ && !locked_) {
      hovered_ = target;
      InvalidateRect(hwnd_, nullptr, FALSE);
    }
  }
  int cx = max(0, min(x, w_));
  int cy = max(0, min(y, h_));
  switch (drag_) {
    case Drag::kCreating:
      sel_ = Normalized(drag_start_.x, drag_start_.y, cx, cy);
      has_sel_ = true;
      InvalidateRect(hwnd_, nullptr, FALSE);
      break;
    case Drag::kMoving: {
      int dx = x - drag_start_.x, dy = y - drag_start_.y;
      int rw = Width(drag_original_), rh = Height(drag_original_);
      int nx = max(0, min(static_cast<int>(drag_original_.left) + dx, w_ - rw));
      int ny = max(0, min(static_cast<int>(drag_original_.top) + dy, h_ - rh));
      sel_ = {nx, ny, nx + rw, ny + rh};
      InvalidateRect(hwnd_, nullptr, FALSE);
      break;
    }
    case Drag::kResizing: {
      int l = drag_original_.left, t = drag_original_.top, r = drag_original_.right, b = drag_original_.bottom;
      if (drag_handle_.dx < 0) l = cx;
      if (drag_handle_.dx > 0) r = cx;
      if (drag_handle_.dy < 0) t = cy;
      if (drag_handle_.dy > 0) b = cy;
      sel_ = Normalized(l, t, r, b);
      InvalidateRect(hwnd_, nullptr, FALSE);
      break;
    }
    case Drag::kNone: {
      Btn hot = HitButton(x, y);
      if (hot != hot_button_) {
        hot_button_ = hot;
        InvalidateRect(hwnd_, nullptr, FALSE);
      }
      break;
    }
  }
  UpdateCursor(x, y);
}

void Overlay::OnMouseUp(int, int) {
  if (drag_ == Drag::kNone) return;
  ReleaseCapture();
  drag_ = Drag::kNone;
  if (Width(sel_) < S(4) || Height(sel_) < S(4)) has_sel_ = false;
  bar_visible_ = true;
  LayoutToolbar();
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void Overlay::OnButton(Btn id) {
  if (finishing_) return;
  switch (id) {
    case kBtnRect: SetShape(Shape::kRect); break;
    case kBtnCircle: SetShape(Shape::kCircle); break;
    case kBtnWindow: SetShape(Shape::kWindow); break;
    case kBtnScreen: ChooseScreen(); break;
    case kBtnVideo: StartRecording(Kind::kVideo); break;
    case kBtnGif: StartRecording(Kind::kGif); break;
    case kBtnCopy: Confirm(Action::kCopy); break;
    case kBtnSave: Confirm(Action::kSave); break;
    case kBtnClose: Finish(OverlayResult(), false, {}, false); break;
    case kBtnSep: break;
  }
}

// ---------------------------------------------------------------- 결과

Bgra Overlay::Crop(RECT r) const {
  r.left = max(r.left, 0L);
  r.top = max(r.top, 0L);
  r.right = min(r.right, static_cast<LONG>(w_));
  r.bottom = min(r.bottom, static_cast<LONG>(h_));
  Bgra out;
  out.width = max(0, Width(r));
  out.height = max(0, Height(r));
  out.pixels.resize(static_cast<size_t>(out.width) * out.height * 4);
  for (int y = 0; y < out.height; ++y) {
    const uint32_t* src = frozen_bits_ + static_cast<size_t>(r.top + y) * w_ + r.left;
    uint32_t* dst = reinterpret_cast<uint32_t*>(out.pixels.data()) + static_cast<size_t>(y) * out.width;
    for (int x = 0; x < out.width; ++x) dst[x] = src[x] | 0xFF000000u;
  }
  return out;
}

bool Overlay::RenderWindow(const WinTarget& t, Bgra* out) const {
  RECT wr;
  if (!GetWindowRect(t.hwnd, &wr) || Width(wr) <= 0 || Height(wr) <= 0) return false;
  HDC screen = GetDC(nullptr);
  HDC dc = CreateCompatibleDC(screen);
  uint32_t* bits = nullptr;
  HBITMAP bmp = CreateDib(screen, Width(wr), Height(wr), &bits);
  ReleaseDC(nullptr, screen);
  if (!dc || !bmp) {
    if (dc) DeleteDC(dc);
    if (bmp) DeleteObject(bmp);
    return false;
  }
  HGDIOBJ old = SelectObject(dc, bmp);
  memset(bits, 0, static_cast<size_t>(Width(wr)) * Height(wr) * 4);
  BOOL ok = PrintWindow(t.hwnd, dc, 2 /* PW_RENDERFULLCONTENT */);
  GdiFlush();
  if (ok) {
    // 그림자는 빼고 보이는 테두리만 자른다.
    RECT frame = {t.rect.left + mon_.left, t.rect.top + mon_.top, t.rect.right + mon_.left, t.rect.bottom + mon_.top};
    RECT crop = {max(frame.left, wr.left) - wr.left, max(frame.top, wr.top) - wr.top,
                 min(frame.right, wr.right) - wr.left, min(frame.bottom, wr.bottom) - wr.top};
    out->width = Width(crop);
    out->height = Height(crop);
    if (out->width > 0 && out->height > 0) {
      out->pixels.resize(static_cast<size_t>(out->width) * out->height * 4);
      for (int y = 0; y < out->height; ++y) {
        const uint32_t* src = bits + static_cast<size_t>(crop.top + y) * Width(wr) + crop.left;
        uint32_t* dst = reinterpret_cast<uint32_t*>(out->pixels.data()) + static_cast<size_t>(y) * out->width;
        for (int x = 0; x < out->width; ++x) dst[x] = src[x] | 0xFF000000u;
      }
    } else {
      ok = FALSE;
    }
  }
  SelectObject(dc, old);
  DeleteObject(bmp);
  DeleteDC(dc);
  return ok != FALSE;
}

// 원형이면 타원 바깥을 투명하게 만든 뒤 PNG로 인코딩한다.
std::vector<uint8_t> Overlay::RenderPng(Bgra* image, bool circle) const {
  if (circle) {
    double rx = image->width / 2.0, ry = image->height / 2.0;
    double r = min(rx, ry);
    uint32_t* px = reinterpret_cast<uint32_t*>(image->pixels.data());
    for (int y = 0; y < image->height; ++y) {
      for (int x = 0; x < image->width; ++x) {
        double nx = (x + 0.5 - rx) / rx, ny = (y + 0.5 - ry) / ry;
        double d = (std::sqrt(nx * nx + ny * ny) - 1.0) * r;  // 경계에서 픽셀 단위 거리
        double a = max(0.0, min(1.0, 0.5 - d));
        uint32_t& p = px[static_cast<size_t>(y) * image->width + x];
        p = (static_cast<uint32_t>(std::lround(a * 255)) << 24) | (p & 0x00FFFFFFu);
      }
    }
  }
  return EncodePng(*image);
}

void Overlay::Confirm(Action action) {
  if (finishing_) return;
  OverlayResult result;
  result.type = OverlayResult::kImage;
  result.image.action = action;
  RECT flash = CurrentRect();
  if (shape_ == Shape::kWindow) {
    if (!locked_) return;
    Bgra image;
    if (!RenderWindow(*locked_, &image)) image = Crop(locked_->rect);  // 가려진 부분은 못 얻으니 화면에서 자른다
    result.image.shape = Shape::kWindow;
    result.image.width = image.width;
    result.image.height = image.height;
    result.image.png = RenderPng(&image, false);
  } else {
    if (!HasSelection()) return;
    bool circle = shape_ == Shape::kCircle;
    Bgra image = Crop(sel_);
    result.image.shape = shape_;
    result.image.width = image.width;
    result.image.height = image.height;
    result.image.png = RenderPng(&image, circle);
  }
  if (result.image.png.empty()) {
    Finish(OverlayResult(), false, {}, false);
    return;
  }
  Finish(std::move(result), true, flash, shape_ == Shape::kCircle);
}

void Overlay::ChooseScreen() {
  Bgra image = Crop({0, 0, w_, h_});
  OverlayResult result;
  result.type = OverlayResult::kImage;
  result.image.action = Action::kCopy;
  result.image.shape = Shape::kScreen;
  result.image.width = image.width;
  result.image.height = image.height;
  result.image.png = EncodePng(image);
  if (result.image.png.empty()) {
    Finish(OverlayResult(), false, {}, false);
    return;
  }
  Finish(std::move(result), true, {0, 0, w_, h_}, false);
}

void Overlay::StartRecording(Kind kind) {
  if (finishing_) return;
  OverlayResult result;
  result.type = OverlayResult::kRecord;
  result.record.kind = kind;
  RECT r;
  if (shape_ == Shape::kWindow) {
    if (!locked_) return;
    r = locked_->rect;
    result.record.window = locked_->hwnd;
  } else {
    if (!HasSelection()) return;
    r = sel_;
  }
  r.left = max(r.left, 0L);
  r.top = max(r.top, 0L);
  r.right = min(r.right, static_cast<LONG>(w_));
  r.bottom = min(r.bottom, static_cast<LONG>(h_));
  result.record.region = {r.left + mon_.left, r.top + mon_.top, r.right + mon_.left, r.bottom + mon_.top};
  Finish(std::move(result), false, {}, false);
}

void Overlay::Finish(OverlayResult result, bool flash, RECT flash_rect, bool flash_circle) {
  if (finishing_) return;
  finishing_ = true;
  result_ = std::move(result);
  bar_visible_ = false;
  if (!flash) {
    Close();
    return;
  }
  flash_rect_ = flash_rect;
  flash_circle_ = flash_circle;
  flash_start_ = GetTickCount();
  SetTimer(hwnd_, kFlashTimer, 15, nullptr);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

// ---------------------------------------------------------------- 그리기

void Overlay::Paint(HDC target) {
  BitBlt(back_dc_, 0, 0, w_, h_, dim_dc_, 0, 0, SRCCOPY);
  RECT r = CurrentRect();
  bool valid = Width(r) > 0 && Height(r) > 0;
  bool circle = shape_ == Shape::kCircle;
  if (valid) {
    if (circle) {
      HRGN rgn = CreateEllipticRgn(r.left, r.top, r.right + 1, r.bottom + 1);
      SelectClipRgn(back_dc_, rgn);
      BitBlt(back_dc_, r.left, r.top, Width(r), Height(r), frozen_dc_, r.left, r.top, SRCCOPY);
      SelectClipRgn(back_dc_, nullptr);
      DeleteObject(rgn);
    } else {
      BitBlt(back_dc_, r.left, r.top, Width(r), Height(r), frozen_dc_, r.left, r.top, SRCCOPY);
    }
  }

  Graphics g(back_dc_);
  g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  g.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
  const Color blue(255, 0, 122, 255);

  if (valid && !finishing_) {
    const float inset = 0.5f;
    if (shape_ == Shape::kWindow) {
      Pen pen(blue, static_cast<float>(S(3)));
      g.DrawRectangle(&pen, static_cast<Gdiplus::REAL>(r.left) + S(1.5), static_cast<Gdiplus::REAL>(r.top) + S(1.5),
                      static_cast<Gdiplus::REAL>(Width(r) - S(3)), static_cast<Gdiplus::REAL>(Height(r) - S(3)));
    } else {
      Pen pen(Color(255, 255, 255, 255), static_cast<float>(1.5 * scale_));
      if (circle) {
        g.DrawEllipse(&pen, static_cast<Gdiplus::REAL>(r.left), static_cast<Gdiplus::REAL>(r.top),
                      static_cast<Gdiplus::REAL>(Width(r)), static_cast<Gdiplus::REAL>(Height(r)));
      } else {
        g.DrawRectangle(&pen, r.left + inset, r.top + inset, static_cast<Gdiplus::REAL>(Width(r)) - 1,
                        static_cast<Gdiplus::REAL>(Height(r)) - 1);
      }
      {
        // 앵커 8개: 10px 흰색 사각형에 파란 테두리 (원형도 바깥 사각형 기준).
        const float a = static_cast<float>(S(10));
        SolidBrush fill(Color(255, 255, 255, 255));
        Pen edge(blue, static_cast<float>(S(1.5)));
        for (int dy = -1; dy <= 1; ++dy) {
          for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) continue;
            float px = dx < 0 ? static_cast<float>(r.left) : dx > 0 ? static_cast<float>(r.right) : (r.left + r.right) / 2.0f;
            float py = dy < 0 ? static_cast<float>(r.top) : dy > 0 ? static_cast<float>(r.bottom) : (r.top + r.bottom) / 2.0f;
            g.FillRectangle(&fill, px - a / 2, py - a / 2, a, a);
            g.DrawRectangle(&edge, px - a / 2, py - a / 2, a, a);
          }
        }
      }
    }

    // 크기 배지: 선택 영역 왼쪽 위.
    wchar_t size_text[64];
    swprintf_s(size_text, L"%d × %d", Width(r), Height(r));
    std::wstring text = size_text;
    const WinTarget* t = locked_ ? locked_ : hovered_;
    if (shape_ == Shape::kWindow && t && !t->title.empty()) {
      std::wstring title = t->title.size() > 40 ? t->title.substr(0, 40) + L"…" : t->title;
      text = title + L" · " + text;
    }
    Gdiplus::FontFamily family(L"Segoe UI");
    Gdiplus::Font font(&family, static_cast<Gdiplus::REAL>(S(12)), Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::RectF bounds;
    g.MeasureString(text.c_str(), -1, &font, Gdiplus::PointF(0, 0), &bounds);
    float bw = bounds.Width + S(12), bh = bounds.Height + S(4);
    float bx = static_cast<float>(r.left);
    float by = r.top - bh - S(6);
    if (by < S(4)) by = static_cast<float>(r.top) + S(6);
    if (bx + bw > w_) bx = w_ - bw - S(4);
    SolidBrush bg(Color(200, 20, 20, 20));
    g.FillRectangle(&bg, bx, by, bw, bh);
    SolidBrush fg(Color(255, 255, 255, 255));
    g.DrawString(text.c_str(), -1, &font, Gdiplus::PointF(bx + S(6), by + S(2)), &fg);
  }

  if (bar_visible_ && !finishing_) DrawToolbar(g);

  if (finishing_ && Width(flash_rect_) > 0) {
    double t = static_cast<double>(GetTickCount() - flash_start_) / kFlashMs;
    t = max(0.0, min(1.0, t));
    int alpha = static_cast<int>(255 * 0.85 * (1.0 - t) * (1.0 - t));  // ease-out
    SolidBrush flash(Color(alpha, 255, 255, 255));
    if (flash_circle_) {
      g.FillEllipse(&flash, static_cast<Gdiplus::REAL>(flash_rect_.left), static_cast<Gdiplus::REAL>(flash_rect_.top),
                    static_cast<Gdiplus::REAL>(Width(flash_rect_)), static_cast<Gdiplus::REAL>(Height(flash_rect_)));
    } else {
      g.FillRectangle(&flash, flash_rect_.left, flash_rect_.top, Width(flash_rect_), Height(flash_rect_));
    }
  }

  BitBlt(target, 0, 0, w_, h_, back_dc_, 0, 0, SRCCOPY);
}

void Overlay::DrawToolbar(Graphics& g) {
  const float radius = static_cast<float>(S(10));
  auto round_rect = [&](const RECT& rc, float rad, Gdiplus::GraphicsPath* path) {
    float d = rad * 2;
    float l = static_cast<float>(rc.left), t = static_cast<float>(rc.top);
    float w = static_cast<float>(Width(rc)), h = static_cast<float>(Height(rc));
    path->AddArc(l, t, d, d, 180, 90);
    path->AddArc(l + w - d, t, d, d, 270, 90);
    path->AddArc(l + w - d, t + h - d, d, d, 0, 90);
    path->AddArc(l, t + h - d, d, d, 90, 90);
    path->CloseFigure();
  };
  {
    Gdiplus::GraphicsPath path;
    round_rect(bar_, radius, &path);
    SolidBrush bg(Color(245, 38, 38, 42));
    g.FillPath(&bg, &path);
    Pen border(Color(90, 255, 255, 255), 1.0f);
    g.DrawPath(&border, &path);
  }
  for (const auto& b : buttons_) {
    if (b.id == kBtnSep) {
      Pen sep(Color(80, 255, 255, 255), 1.0f);
      int x = (b.rect.left + b.rect.right) / 2;
      g.DrawLine(&sep, x, b.rect.top + S(5), x, b.rect.bottom - S(5));
      continue;
    }
    bool active = (b.id == kBtnRect && shape_ == Shape::kRect) || (b.id == kBtnCircle && shape_ == Shape::kCircle) ||
                  (b.id == kBtnWindow && shape_ == Shape::kWindow);
    if (active || b.id == hot_button_) {
      Gdiplus::GraphicsPath path;
      round_rect(b.rect, static_cast<float>(S(6)), &path);
      SolidBrush hl(active ? Color(255, 0, 122, 255) : Color(60, 255, 255, 255));
      g.FillPath(&hl, &path);
    }
    DrawIcon(g, b.id, b.rect);
  }

  // 마우스를 올린 단추의 설명.
  if (hot_button_ != kBtnSep) {
    std::wstring label;
    switch (hot_button_) {
      case kBtnRect: label = L"사각형"; break;
      case kBtnCircle: label = L"원형"; break;
      case kBtnWindow: label = L"창 선택"; break;
      case kBtnScreen: label = L"화면 전체"; break;
      case kBtnVideo: label = L"영상 녹화 (최대 " + std::to_wstring(CaptureConfig::max_seconds) + L"초)"; break;
      case kBtnGif: label = L"GIF 녹화 (최대 " + std::to_wstring(CaptureConfig::max_seconds) + L"초)"; break;
      case kBtnCopy: label = L"복사"; break;
      case kBtnSave: label = L"저장"; break;
      case kBtnClose: label = L"닫기"; break;
      default: break;
    }
    Gdiplus::FontFamily family(L"Segoe UI");
    Gdiplus::Font font(&family, static_cast<Gdiplus::REAL>(S(12)), Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::RectF bounds;
    g.MeasureString(label.c_str(), -1, &font, Gdiplus::PointF(0, 0), &bounds);
    float tw = bounds.Width + S(12), th = bounds.Height + S(6);
    RECT hot = {};
    for (const auto& b : buttons_) if (b.id == hot_button_) hot = b.rect;
    float tx = (hot.left + hot.right) / 2.0f - tw / 2;
    tx = max(static_cast<float>(S(4)), min(tx, w_ - tw - S(4)));
    float ty = bar_.top - th - S(6);
    if (ty < S(4)) ty = static_cast<float>(bar_.bottom) + S(6);
    SolidBrush bg(Color(235, 20, 20, 22));
    g.FillRectangle(&bg, tx, ty, tw, th);
    SolidBrush fg(Color(255, 255, 255, 255));
    g.DrawString(label.c_str(), -1, &font, Gdiplus::PointF(tx + S(6), ty + S(3)), &fg);
  }
}

void Overlay::DrawIcon(Graphics& g, Btn id, const RECT& r) {
  const float cx = (r.left + r.right) / 2.0f, cy = (r.top + r.bottom) / 2.0f;
  const float u = static_cast<float>(scale_);
  Pen pen(Color(255, 255, 255, 255), 1.6f * u);
  pen.SetLineJoin(Gdiplus::LineJoinRound);
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  SolidBrush white(Color(255, 255, 255, 255));
  switch (id) {
    case kBtnRect:
      g.DrawRectangle(&pen, cx - 7 * u, cy - 6 * u, 14 * u, 12 * u);
      break;
    case kBtnCircle:
      g.DrawEllipse(&pen, cx - 7 * u, cy - 7 * u, 14 * u, 14 * u);
      break;
    case kBtnWindow:
      g.DrawRectangle(&pen, cx - 8 * u, cy - 6 * u, 16 * u, 12 * u);
      g.DrawLine(&pen, cx - 8 * u, cy - 2 * u, cx + 8 * u, cy - 2 * u);
      break;
    case kBtnScreen:
      g.DrawRectangle(&pen, cx - 8 * u, cy - 7 * u, 16 * u, 10 * u);
      g.DrawLine(&pen, cx - 4 * u, cy + 7 * u, cx + 4 * u, cy + 7 * u);
      g.DrawLine(&pen, cx, cy + 3 * u, cx, cy + 7 * u);
      break;
    case kBtnVideo: {
      g.DrawRectangle(&pen, cx - 9 * u, cy - 5 * u, 11 * u, 10 * u);
      Gdiplus::PointF tri[3] = {{cx + 4 * u, cy}, {cx + 10 * u, cy - 4 * u}, {cx + 10 * u, cy + 4 * u}};
      g.FillPolygon(&white, tri, 3);
      break;
    }
    case kBtnGif: {
      Gdiplus::FontFamily family(L"Segoe UI");
      Gdiplus::Font font(&family, 11.0f * u, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
      Gdiplus::StringFormat fmt;
      fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
      fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
      g.DrawString(L"GIF", -1, &font, Gdiplus::PointF(cx, cy), &fmt, &white);
      break;
    }
    case kBtnCopy:
      g.DrawRectangle(&pen, cx - 7 * u, cy - 3 * u, 10 * u, 10 * u);
      g.DrawLines(&pen, std::vector<Gdiplus::PointF>{{cx - 3 * u, cy - 6 * u}, {cx - 3 * u, cy - 8 * u},
                                                      {cx + 7 * u, cy - 8 * u}, {cx + 7 * u, cy + 2 * u},
                                                      {cx + 5 * u, cy + 2 * u}}.data(), 5);
      break;
    case kBtnSave:
      g.DrawLine(&pen, cx, cy - 8 * u, cx, cy + 3 * u);
      g.DrawLine(&pen, cx - 4 * u, cy - 1 * u, cx, cy + 3 * u);
      g.DrawLine(&pen, cx + 4 * u, cy - 1 * u, cx, cy + 3 * u);
      g.DrawLine(&pen, cx - 7 * u, cy + 7 * u, cx + 7 * u, cy + 7 * u);
      break;
    case kBtnClose:
      g.DrawLine(&pen, cx - 6 * u, cy - 6 * u, cx + 6 * u, cy + 6 * u);
      g.DrawLine(&pen, cx + 6 * u, cy - 6 * u, cx - 6 * u, cy + 6 * u);
      break;
    case kBtnSep:
      break;
  }
}

// ---------------------------------------------------------------- 창 프로시저

LRESULT CALLBACK Overlay::WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
  }
  auto* self = reinterpret_cast<Overlay*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (!self || self != g_overlay) return DefWindowProcW(hwnd, msg, wp, lp);
  return self->OnMessage(hwnd, msg, wp, lp);
}

LRESULT Overlay::OnMessage(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  const int x = static_cast<short>(LOWORD(lp));
  const int y = static_cast<short>(HIWORD(lp));
  switch (msg) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd_, &ps);
      Paint(dc);
      EndPaint(hwnd_, &ps);
      return 0;
    }
    case WM_SETCURSOR:
      if (LOWORD(lp) == HTCLIENT) {
        SetCursor(cursor_);
        return TRUE;
      }
      break;
    case WM_LBUTTONDOWN:
      OnMouseDown(x, y);
      return 0;
    case WM_MOUSEMOVE:
      OnMouseMove(x, y);
      return 0;
    case WM_LBUTTONUP:
      OnMouseUp(x, y);
      return 0;
    case WM_RBUTTONDOWN:
      Finish(OverlayResult(), false, {}, false);
      return 0;
    case WM_KEYDOWN:
      if (wp == VK_ESCAPE) {
        Finish(OverlayResult(), false, {}, false);
      } else if (wp == VK_RETURN) {
        Confirm(Action::kCopy);
      }
      return 0;
    case WM_TIMER:
      if (wp == kFlashTimer) {
        if (GetTickCount() - flash_start_ >= kFlashMs) {
          KillTimer(hwnd_, kFlashTimer);
          Close();  // this가 지워진다. 이후 멤버를 쓰지 않는다.
        } else {
          InvalidateRect(hwnd_, nullptr, FALSE);
        }
      }
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

}  // namespace

bool RunOverlay(Shape initial, OverlayCallback callback) {
  if (g_overlay) return false;
  g_overlay = new Overlay();
  if (!g_overlay->Start(initial, std::move(callback))) {
    delete g_overlay;
    g_overlay = nullptr;
    return false;
  }
  return true;
}

bool OverlayActive() { return g_overlay != nullptr; }

}  // namespace snapdock
