import Cocoa
import ScreenCaptureKit

/// 영역 선택 오버레이의 결과. `png`는 선택 모양(원형이면 바깥이 투명)으로 잘린 이미지다.
struct CaptureOutcome {
  enum Action: String { case copy, save }

  let action: Action
  let shape: CaptureShape
  let png: Data
  let width: Int
  let height: Int
}

enum CaptureShape: String {
  case rect, circle
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
        let image = try await Self.snapshot(of: screen)
        self.present(image: image, on: screen, shape: shape)
      } catch {
        self.finish(.failure(error))
      }
    }
  }

  private static func snapshot(of screen: NSScreen) async throws -> CGImage {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      throw CaptureError.noDisplay
    }
    let displayID = CGDirectDisplayID(number.uint32Value)
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
      throw CaptureError.noDisplay
    }
    let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
    let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
    let config = SCStreamConfiguration()
    let scale = screen.backingScaleFactor
    config.width = Int(CGFloat(display.width) * scale)
    config.height = Int(CGFloat(display.height) * scale)
    config.showsCursor = false
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
  }

  private func present(image: CGImage, on screen: NSScreen, shape: CaptureShape) {
    let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
    window.level = .screenSaver
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false

    let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image, shape: shape)
    view.onFinish = { [weak self] outcome in self?.finish(.success(outcome)) }
    window.contentView = view
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
  }

  private func finish(_ result: Result<CaptureOutcome?, Error>) {
    window?.orderOut(nil)
    window?.contentView = nil
    window = nil
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

  var onFinish: ((CaptureOutcome?) -> Void)?

  private let image: CGImage
  private var shape: CaptureShape
  private var selection: NSRect?
  private var drag: Drag?
  private var toolbar: NSView?
  private var rectButton: NSButton?
  private var circleButton: NSButton?

  private let handleSize: CGFloat = 10
  private let minSide: CGFloat = 8
  private let accent = NSColor(srgbRed: 0x37 / 255, green: 0x8A / 255, blue: 0xDD / 255, alpha: 1)

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  init(frame: NSRect, image: CGImage, shape: CaptureShape) {
    self.image = image
    self.shape = shape
    super.init(frame: frame)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  // MARK: 그리기

  private func path(for r: NSRect) -> NSBezierPath {
    shape == .circle ? NSBezierPath(ovalIn: r) : NSBezierPath(rect: r)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSImage(cgImage: image, size: bounds.size).draw(in: bounds)

    let dim = NSBezierPath(rect: bounds)
    if let r = selection {
      dim.append(path(for: r))
      dim.windingRule = .evenOdd
    }
    NSColor.black.withAlphaComponent(0.45).setFill()
    dim.fill()

    guard let r = selection else { return }
    let outline = path(for: r)
    outline.lineWidth = 1.5
    NSColor.white.setStroke()
    outline.stroke()

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

    drawSizeBadge(for: r)
  }

  private func drawSizeBadge(for r: NSRect) {
    let (w, h) = pixelSize(of: r)
    let text = "\(w) × \(h)" as NSString
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

  private func hitHandle(at p: NSPoint) -> Handle? {
    guard let r = selection else { return nil }
    let slop = handleSize
    return Handle.allCases.first { h in
      let hp = h.point(in: r)
      return abs(hp.x - p.x) <= slop && abs(hp.y - p.y) <= slop
    }
  }

  override func mouseMoved(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
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
    drag = nil
    if let r = selection, r.width < minSide || r.height < minSide {
      selection = nil
    }
    needsDisplay = true
    if selection != nil { showToolbar() }
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

  private func separator() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor.separatorColor.cgColor
    v.widthAnchor.constraint(equalToConstant: 1).isActive = true
    v.heightAnchor.constraint(equalToConstant: 20).isActive = true
    return v
  }

  private func showToolbar() {
    hideToolbar()
    guard let r = selection else { return }

    let rectB = makeButton("square", label: "사각형", action: #selector(pickRect))
    let circleB = makeButton("circle", label: "원형", action: #selector(pickCircle))
    let copyB = makeButton("doc.on.doc", label: "복사", action: #selector(copyTapped))
    let saveB = makeButton("arrow.down.to.line", label: "저장", action: #selector(saveTapped))
    let closeB = makeButton("xmark", label: "닫기", action: #selector(closeTapped))
    rectButton = rectB
    circleButton = circleB

    let stack = NSStackView(views: [rectB, circleB, separator(), copyB, saveB, closeB])
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
    var y = r.maxY + 10
    if y + size.height + 4 > bounds.height { y = r.minY - size.height - 10 }
    if y < 4 { y = r.maxY - size.height - 10 }
    let x = min(max(4, r.midX - size.width / 2), bounds.width - size.width - 4)
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
    for (button, mine) in [(rectButton, CaptureShape.rect), (circleButton, CaptureShape.circle)] {
      let on = shape == mine
      button?.contentTintColor = on ? accent : .labelColor
      button?.layer?.backgroundColor = on ? accent.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
    }
  }

  @objc private func pickRect() { setShape(.rect) }
  @objc private func pickCircle() { setShape(.circle) }
  @objc private func copyTapped() { confirm(.copy) }
  @objc private func saveTapped() { confirm(.save) }
  @objc private func closeTapped() { onFinish?(nil) }

  private func setShape(_ s: CaptureShape) {
    shape = s
    refreshShapeButtons()
    needsDisplay = true
  }

  // MARK: 결과

  private func confirm(_ action: CaptureOutcome.Action) {
    guard let r = selection else { return }
    guard let png = renderPNG(of: r) else {
      onFinish?(nil)
      return
    }
    let (w, h) = pixelSize(of: r)
    onFinish?(CaptureOutcome(action: action, shape: shape, png: png, width: w, height: h))
  }

  /// 선택 영역을 픽셀 단위로 잘라 PNG로 만든다. 원형이면 바깥을 투명하게 둔다.
  private func renderPNG(of r: NSRect) -> Data? {
    let s = pixelScale
    let px = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
      .integral
      .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
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
