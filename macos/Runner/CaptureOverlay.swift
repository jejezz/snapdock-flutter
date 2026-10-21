import Cocoa
import ScreenCaptureKit

/// 영역 선택 오버레이의 결과. `png`는 선택 모양(원형이면 바깥이 투명)으로 잘린 이미지다.
struct CaptureOutcome {
  enum Action: String { case copy, save }
  enum Kind: String { case image, video, gif }

  let action: Action
  let shape: CaptureShape
  /// 이미지면 결과 PNG, 영상·GIF면 썸네일 PNG.
  let png: Data
  let width: Int
  let height: Int
  var kind: Kind = .image
  /// 영상·GIF 파일 경로.
  var path: String?
  var durationMs: Int?
}

/// 오버레이가 닫히면서 돌려주는 것: 다 만든 이미지, 또는 이어서 할 녹화 요청.
enum OverlayResult {
  case image(CaptureOutcome)
  case record(RecordRequest)
}

enum CaptureShape: String {
  case rect, circle, window, screen
}

/// 창 선택 모드에서 가리킬 수 있는 창. `rect`는 오버레이 뷰 좌표(왼쪽 위 원점, 포인트)다.
struct WindowTarget {
  let window: SCWindow
  let rect: CGRect
  let title: String
}

enum CaptureError: Error {
  case permissionDenied
  case noDisplay
  case imageFailed
}

/// 마우스가 있는 디스플레이를 얼려 놓고(freeze-frame) 그 위에 선택 오버레이를 띄운다.
/// 얼린 이미지에서 잘라 내므로 오버레이 자체가 캡처에 찍히지 않고, 우리 앱 창은
/// 필터에서 제외해 독이 찍히지 않는다.
@MainActor
final class CaptureOverlayController {
  static let shared = CaptureOverlayController()

  private var window: OverlayWindow?
  private var screen: NSScreen?
  private var display: SCDisplay?
  private var ownApps: [SCRunningApplication] = []
  private var completion: ((Result<CaptureOutcome?, Error>) -> Void)?

  var isActive: Bool { window != nil }

  func run(shape: CaptureShape, completion: @escaping (Result<CaptureOutcome?, Error>) -> Void) {
    guard window == nil else {
      completion(.success(nil))
      return
    }
    guard CGPreflightScreenCaptureAccess() else {
      completion(.failure(CaptureError.permissionDenied))
      return
    }
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
      completion(.failure(CaptureError.noDisplay))
      return
    }
    self.completion = completion
    Task { @MainActor in
      do {
        let (image, windows) = try await Self.snapshot(of: screen)
        self.present(image: image, windows: windows, on: screen, shape: shape)
      } catch {
        self.finish(.failure(error))
      }
    }
  }

  private static func snapshot(of screen: NSScreen) async throws -> (CGImage, [WindowTarget]) {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      throw CaptureError.noDisplay
    }
    let displayID = CGDirectDisplayID(number.uint32Value)
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
      throw CaptureError.noDisplay
    }
    let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
    shared.display = display
    shared.ownApps = ownApps
    let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
    let config = SCStreamConfiguration()
    let scale = screen.backingScaleFactor
    config.width = Int(CGFloat(display.width) * scale)
    config.height = Int(CGFloat(display.height) * scale)
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    return (image, windowTargets(in: content, display: display))
  }

  /// 이 디스플레이 위에서 가리킬 수 있는 일반 창을 앞에 있는 순서대로 모은다.
  private static func windowTargets(in content: SCShareableContent, display: SCDisplay) -> [WindowTarget] {
    let origin = CGDisplayBounds(display.displayID).origin
    let bounds = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))

    // SCShareableContent는 앞뒤 순서를 보장하지 않아서, 순서만 CGWindowList에서 빌린다.
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var order: [CGWindowID: Int] = [:]
    for (index, entry) in info.enumerated() {
      if let number = entry[kCGWindowNumber as String] as? CGWindowID { order[number] = index }
    }

    let own = Bundle.main.bundleIdentifier
    return content.windows
      .filter { $0.isOnScreen && $0.windowLayer == 0 && $0.owningApplication?.bundleIdentifier != own }
      .compactMap { w -> (Int, WindowTarget)? in
        let rect = w.frame.offsetBy(dx: -origin.x, dy: -origin.y).intersection(bounds)
        guard !rect.isNull, rect.width >= 40, rect.height >= 40 else { return nil }
        let title = [w.owningApplication?.applicationName, w.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        return (order[w.windowID] ?? Int.max, WindowTarget(window: w, rect: rect, title: title))
      }
      .sorted { $0.0 < $1.0 }
      .map { $0.1 }
  }

  private func present(image: CGImage, windows: [WindowTarget], on screen: NSScreen, shape: CaptureShape) {
    let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
    window.level = .screenSaver
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false

    let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image, windows: windows, shape: shape)
    view.onFinish = { [weak self] result in self?.overlayFinished(result) }
    window.contentView = view
    self.window = window
    self.screen = screen

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
  }

  private func overlayFinished(_ result: OverlayResult?) {
    switch result {
    case nil:
      finish(.success(nil))
    case .image(let outcome)?:
      finish(.success(outcome))
    case .record(let request)?:
      guard let screen, let display else {
        finish(.success(nil))
        return
      }
      closeOverlay()
      let ownApps = self.ownApps
      Task { @MainActor in
        do {
          let outcome = try await RecordingSession(request: request, screen: screen, display: display, ownApps: ownApps).run()
          self.finish(.success(outcome))
        } catch {
          self.finish(.failure(error))
        }
      }
    }
  }

  private func closeOverlay() {
    window?.orderOut(nil)
    window?.contentView = nil
    window = nil
  }

  private func finish(_ result: Result<CaptureOutcome?, Error>) {
    closeOverlay()
    let done = completion
    completion = nil
    done?(result)
  }
}

private final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

// MARK: - 오버레이 뷰

private enum Handle: CaseIterable {
  case nw, n, ne, e, se, s, sw, w

  /// -1: 왼쪽/위 변을 움직인다, 0: 그 축은 그대로, 1: 오른쪽/아래 변을 움직인다.
  var dx: Int {
    switch self {
    case .nw, .w, .sw: return -1
    case .n, .s: return 0
    case .ne, .e, .se: return 1
    }
  }

  var dy: Int {
    switch self {
    case .nw, .n, .ne: return -1
    case .w, .e: return 0
    case .sw, .s, .se: return 1
    }
  }

  func point(in r: NSRect) -> NSPoint {
    let x = dx < 0 ? r.minX : (dx > 0 ? r.maxX : r.midX)
    let y = dy < 0 ? r.minY : (dy > 0 ? r.maxY : r.midY)
    return NSPoint(x: x, y: y)
  }
}

private final class OverlayView: NSView {
  private enum Drag {
    case creating(start: NSPoint)
    case moving(grab: NSPoint, original: NSRect)
    case resizing(Handle, original: NSRect)
  }

  var onFinish: ((OverlayResult?) -> Void)?

  private let image: CGImage
  private let windows: [WindowTarget]
  private var shape: CaptureShape
  private var selection: NSRect?
  /// 창 모드에서 클릭해 고정한 창. 있으면 선택 영역은 그 창이고 앵커는 숨긴다.
  private var locked: WindowTarget?
  private var hovered: WindowTarget?
  private var drag: Drag?
  private var confirming = false
  private var toolbar: NSView?
  private var shapeButtons: [(NSButton, CaptureShape)] = []

  private let handleSize: CGFloat = 10
  private let minSide: CGFloat = 8
  private let accent = NSColor(srgbRed: 0x37 / 255, green: 0x8A / 255, blue: 0xDD / 255, alpha: 1)

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  init(frame: NSRect, image: CGImage, windows: [WindowTarget], shape: CaptureShape) {
    self.image = image
    self.windows = windows
    self.shape = (shape == .screen) ? .rect : shape
    super.init(frame: frame)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil, toolbar == nil { showToolbar() }
  }

  // MARK: 그리기

  private func path(for r: NSRect) -> NSBezierPath {
    shape == .circle ? NSBezierPath(ovalIn: r) : NSBezierPath(rect: r)
  }

  /// 지금 밝게 보여 줄 영역: 고른 영역, 없으면 창 모드에서 마우스 아래의 창.
  private var activeRect: NSRect? {
    if let selection { return selection }
    if shape == .window { return hovered?.rect }
    return nil
  }

  override func draw(_ dirtyRect: NSRect) {
    NSImage(cgImage: image, size: bounds.size).draw(in: bounds)

    let active = activeRect
    let dim = NSBezierPath(rect: bounds)
    if let r = active {
      dim.append(path(for: r))
      dim.windingRule = .evenOdd
    }
    NSColor.black.withAlphaComponent(0.45).setFill()
    dim.fill()

    guard let r = active else { return }
    let outline = path(for: r)
    let hoverOnly = selection == nil
    outline.lineWidth = hoverOnly ? 3 : 1.5
    (hoverOnly ? accent : NSColor.white).setStroke()
    outline.stroke()

    if selection != nil, locked == nil {
      for h in Handle.allCases {
        let p = h.point(in: r)
        let box = NSRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2, width: handleSize, height: handleSize)
        let square = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
        NSColor.white.setFill()
        square.fill()
        accent.setStroke()
        square.lineWidth = 1.5
        square.stroke()
      }
    }

    drawSizeBadge(for: r, title: (locked ?? hovered)?.title)
  }

  private func drawSizeBadge(for r: NSRect, title: String?) {
    let (w, h) = pixelSize(of: r)
    var label = "\(w) × \(h)"
    if shape == .window, let title, !title.isEmpty {
      let clipped = title.count > 48 ? String(title.prefix(47)) + "…" : title
      label = "\(clipped)  ·  \(label)"
    }
    let text = label as NSString
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      .foregroundColor: NSColor.white,
    ]
    let size = text.size(withAttributes: attrs)
    let pill = NSRect(x: max(4, r.minX), y: max(4, r.minY - size.height - 12), width: size.width + 16, height: size.height + 4)
    NSColor.black.withAlphaComponent(0.75).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
    text.draw(at: NSPoint(x: pill.minX + 8, y: pill.minY + 2), withAttributes: attrs)
  }

  private var pixelScale: CGFloat { CGFloat(image.width) / bounds.width }

  private func pixelSize(of r: NSRect) -> (Int, Int) {
    (Int((r.width * pixelScale).rounded()), Int((r.height * pixelScale).rounded()))
  }

  // MARK: 마우스

  private func window(at p: NSPoint) -> WindowTarget? {
    windows.first { $0.rect.contains(p) }
  }

  private func hitHandle(at p: NSPoint) -> Handle? {
    guard let r = selection, locked == nil else { return nil }
    let slop = handleSize
    return Handle.allCases.first { h in
      let hp = h.point(in: r)
      return abs(hp.x - p.x) <= slop && abs(hp.y - p.y) <= slop
    }
  }

  override func mouseMoved(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if shape == .window {
      if selection == nil {
        let target = window(at: p)
        if target?.window.windowID != hovered?.window.windowID {
          hovered = target
          needsDisplay = true
        }
      }
      (window(at: p) != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
      return
    }
    if let h = hitHandle(at: p) {
      switch (h.dx, h.dy) {
      case (0, _): NSCursor.resizeUpDown.set()
      case (_, 0): NSCursor.resizeLeftRight.set()
      default: NSCursor.crosshair.set()
      }
    } else if let r = selection, r.contains(p) {
      NSCursor.openHand.set()
    } else {
      NSCursor.crosshair.set()
    }
  }

  override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)

    if shape == .window {
      if let target = window(at: p), locked == nil || !(selection?.contains(p) ?? false) {
        locked = target
        hovered = target
        selection = target.rect
      } else if locked != nil, !(selection?.contains(p) ?? false) {
        locked = nil
        selection = nil
      }
      showToolbar()
      needsDisplay = true
      return
    }

    hideToolbar()
    if let h = hitHandle(at: p), let r = selection {
      drag = .resizing(h, original: r)
    } else if let r = selection, r.contains(p) {
      drag = .moving(grab: p, original: r)
      NSCursor.closedHand.set()
    } else {
      selection = nil
      drag = .creating(start: p)
    }
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard let drag else { return }
    let p = clamp(convert(event.locationInWindow, from: nil))
    switch drag {
    case .creating(let start):
      selection = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
    case .moving(let grab, let original):
      var r = original.offsetBy(dx: p.x - grab.x, dy: p.y - grab.y)
      r.origin.x = min(max(0, r.origin.x), bounds.width - r.width)
      r.origin.y = min(max(0, r.origin.y), bounds.height - r.height)
      selection = r
    case .resizing(let h, let original):
      var xs = (original.minX, original.maxX)
      var ys = (original.minY, original.maxY)
      if h.dx < 0 { xs = (p.x, original.maxX) } else if h.dx > 0 { xs = (original.minX, p.x) }
      if h.dy < 0 { ys = (p.y, original.maxY) } else if h.dy > 0 { ys = (original.minY, p.y) }
      selection = NSRect(x: min(xs.0, xs.1), y: min(ys.0, ys.1), width: abs(xs.1 - xs.0), height: abs(ys.1 - ys.0))
    }
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    guard drag != nil else { return }
    drag = nil
    if let r = selection, r.width < minSide || r.height < minSide {
      selection = nil
    }
    needsDisplay = true
    showToolbar()
  }

  private func clamp(_ p: NSPoint) -> NSPoint {
    NSPoint(x: min(max(0, p.x), bounds.width), y: min(max(0, p.y), bounds.height))
  }

  // MARK: 키보드

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53: onFinish?(nil) // Esc
    case 36, 76: confirm(.copy) // Return, Enter
    default: super.keyDown(with: event)
    }
  }

  // MARK: 툴바

  private func symbol(_ name: String, _ label: String) -> NSImage {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: label) ?? NSImage()
    return image.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) ?? image
  }

  private func makeButton(_ symbolName: String, label: String, action: Selector) -> NSButton {
    let b = NSButton(image: symbol(symbolName, label), target: self, action: action)
    b.isBordered = false
    b.toolTip = label
    b.imagePosition = .imageOnly
    b.wantsLayer = true
    b.layer?.cornerRadius = 8
    b.widthAnchor.constraint(equalToConstant: 32).isActive = true
    b.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return b
  }

  private func makeGIFButton() -> NSButton {
    let b = NSButton(title: "GIF", target: self, action: #selector(recordGIFTapped))
    b.isBordered = false
    b.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    b.toolTip = "GIF 녹화 (최대 \(Int(CaptureConfig.maxRecordingSeconds))초)"
    b.widthAnchor.constraint(equalToConstant: 36).isActive = true
    b.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return b
  }

  private func separator() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor.separatorColor.cgColor
    v.widthAnchor.constraint(equalToConstant: 1).isActive = true
    v.heightAnchor.constraint(equalToConstant: 20).isActive = true
    return v
  }

  /// 툴바는 처음부터 화면 아래 가운데에 떠 있고, 영역을 고르면 그 영역 곁으로 옮겨 간다.
  private func showToolbar() {
    hideToolbar()

    let rectB = makeButton("square", label: "사각형", action: #selector(pickRect))
    let circleB = makeButton("circle", label: "원형", action: #selector(pickCircle))
    let windowB = makeButton("macwindow", label: "창", action: #selector(pickWindow))
    let screenB = makeButton("display", label: "화면 전체", action: #selector(screenTapped))
    shapeButtons = [(rectB, .rect), (circleB, .circle), (windowB, .window)]

    var views: [NSView] = [rectB, circleB, windowB, screenB]
    if selection != nil {
      views.append(separator())
      views.append(makeButton("video", label: "영상 녹화 (최대 \(Int(CaptureConfig.maxRecordingSeconds))초)", action: #selector(recordVideoTapped)))
      views.append(makeGIFButton())
      views.append(separator())
      views.append(makeButton("doc.on.doc", label: "복사", action: #selector(copyTapped)))
      views.append(makeButton("arrow.down.to.line", label: "저장", action: #selector(saveTapped)))
    }
    views.append(separator())
    views.append(makeButton("xmark", label: "닫기", action: #selector(closeTapped)))

    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.spacing = 2
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

    let bar = NSVisualEffectView()
    bar.material = .menu
    bar.state = .active
    bar.wantsLayer = true
    bar.layer?.cornerRadius = 10
    bar.layer?.borderWidth = 0.5
    bar.layer?.borderColor = NSColor.separatorColor.cgColor
    bar.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
      stack.topAnchor.constraint(equalTo: bar.topAnchor),
      stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
    ])
    let size = stack.fittingSize

    let x: CGFloat
    var y: CGFloat
    if let r = selection {
      y = r.maxY + 10
      if y + size.height + 4 > bounds.height { y = r.minY - size.height - 10 }
      if y < 4 { y = r.maxY - size.height - 10 }
      x = min(max(4, r.midX - size.width / 2), bounds.width - size.width - 4)
    } else {
      y = bounds.height - size.height - 48
      x = bounds.midX - size.width / 2
    }
    bar.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    addSubview(bar)
    toolbar = bar
    refreshShapeButtons()
  }

  private func hideToolbar() {
    toolbar?.removeFromSuperview()
    toolbar = nil
  }

  private func refreshShapeButtons() {
    for (button, mine) in shapeButtons {
      let on = shape == mine
      button.contentTintColor = on ? accent : .labelColor
      button.layer?.backgroundColor = on ? accent.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
    }
  }

  @objc private func pickRect() { setShape(.rect) }
  @objc private func pickCircle() { setShape(.circle) }
  @objc private func pickWindow() { setShape(.window) }
  @objc private func recordVideoTapped() { startRecording(.video) }
  @objc private func recordGIFTapped() { startRecording(.gif) }
  @objc private func copyTapped() { confirm(.copy) }
  @objc private func saveTapped() { confirm(.save) }
  @objc private func closeTapped() { onFinish?(nil) }

  @objc private func screenTapped() {
    guard let png = renderPNG(cropping: CGRect(x: 0, y: 0, width: image.width, height: image.height), as: .rect) else {
      onFinish?(nil)
      return
    }
    onFinish?(.image(CaptureOutcome(action: .copy, shape: .screen, png: png, width: image.width, height: image.height)))
  }

  private func setShape(_ s: CaptureShape) {
    guard shape != s else { return }
    shape = s
    if s == .window {
      selection = nil
      locked = nil
      hovered = nil
    } else if locked != nil {
      // 고정한 창의 영역을 그대로 가져와 사각형/원형으로 다듬을 수 있게 한다.
      locked = nil
    }
    showToolbar()
    needsDisplay = true
  }

  // MARK: 결과

  /// 고른 영역(원형이어도 둘러싼 사각형)이나 고정한 창을 녹화하라고 넘긴다.
  private func startRecording(_ kind: RecordingKind) {
    guard let r = selection, !confirming else { return }
    confirming = true
    if let target = locked {
      onFinish?(.record(RecordRequest(kind: kind, sourceRect: nil, window: target.window)))
    } else {
      onFinish?(.record(RecordRequest(kind: kind, sourceRect: r, window: nil)))
    }
  }

  private func confirm(_ action: CaptureOutcome.Action) {
    guard let r = selection, !confirming else { return }
    if let target = locked {
      renderWindow(target, action: action)
      return
    }
    let s = pixelScale
    let crop = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
    guard let png = renderPNG(cropping: crop, as: shape) else {
      onFinish?(nil)
      return
    }
    let (w, h) = pixelSize(of: r)
    onFinish?(.image(CaptureOutcome(action: action, shape: shape, png: png, width: w, height: h)))
  }

  /// 창 하나를 가려진 부분까지 포함해 그 창만 찍는다 (그림자는 뺀다).
  private func renderWindow(_ target: WindowTarget, action: CaptureOutcome.Action) {
    confirming = true
    let scale = pixelScale
    Task { @MainActor in
      do {
        let filter = SCContentFilter(desktopIndependentWindow: target.window)
        let config = SCStreamConfiguration()
        config.width = Int((target.window.frame.width * scale).rounded())
        config.height = Int((target.window.frame.height * scale).rounded())
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let shot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let png = NSBitmapImageRep(cgImage: shot).representation(using: .png, properties: [:]) else {
          onFinish?(nil)
          return
        }
        onFinish?(.image(CaptureOutcome(action: action, shape: .window, png: png, width: shot.width, height: shot.height)))
      } catch {
        onFinish?(nil)
      }
    }
  }

  /// 얼린 화면에서 픽셀 단위로 잘라 PNG로 만든다. 원형이면 바깥을 투명하게 둔다.
  private func renderPNG(cropping rect: CGRect, as shape: CaptureShape) -> Data? {
    let px = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard px.width >= 1, px.height >= 1, var cropped = image.cropping(to: px) else { return nil }

    if shape == .circle {
      let w = cropped.width, h = cropped.height
      let space = cropped.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
      guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
      ctx.addEllipse(in: CGRect(x: 0, y: 0, width: w, height: h))
      ctx.clip()
      ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
      guard let masked = ctx.makeImage() else { return nil }
      cropped = masked
    }
    return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
  }
}
