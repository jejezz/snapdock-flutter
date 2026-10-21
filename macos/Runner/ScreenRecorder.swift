import AVFoundation
import Cocoa
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// 사용자가 설정에서 바꾸는 값. Flutter가 `configure`로 보내 준다.
enum CaptureConfig {
  /// 녹화 길이 제한(초). 기본 10초.
  static var maxRecordingSeconds: Double = 10
  /// nil이면 ~/Pictures/Snapdock. 이미지(PNG)와 GIF가 간다.
  static var imageDirectory: URL?
  /// nil이면 ~/Movies/Snapdock. 영상(MP4)이 간다.
  static var videoDirectory: URL?

  static func saveFolder(movies: Bool) -> URL? {
    if let custom = movies ? videoDirectory : imageDirectory { return custom }
    let base: FileManager.SearchPathDirectory = movies ? .moviesDirectory : .picturesDirectory
    return FileManager.default.urls(for: base, in: .userDomainMask).first?.appendingPathComponent("Snapdock", isDirectory: true)
  }
}

enum RecordingLimits {
  static let videoFPS = 30
  static let gifRecordFPS = 15
  static let gifFPS = 10
  static let gifMaxWidth: CGFloat = 720
}

enum RecordingKind: String {
  case video, gif
}

/// 오버레이가 녹화를 시작하라고 넘기는 요청. 대상은 영역(디스플레이의 일부) 또는 창 하나다.
struct RecordRequest {
  let kind: RecordingKind
  /// 영역 녹화일 때 디스플레이 기준 좌표(포인트, 왼쪽 위 원점).
  let sourceRect: CGRect?
  /// 창 녹화일 때 그 창.
  let window: SCWindow?
}

enum RecordingError: Error {
  case noFrames
  case writerFailed(String)
}

// MARK: - 녹화기

/// ScreenCaptureKit 스트림을 H.264 MP4로 쓴다. 화면이 멈춰 있으면 프레임이 안 오므로,
/// 끝낼 때 현재 시각으로 세션을 닫아 영상 길이가 실제 녹화 시간과 같게 한다.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
  let url: URL
  private let stream: SCStream
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let queue = DispatchQueue(label: "art.zoomon.snapdock.recorder")
  private var sessionStarted = false

  init(filter: SCContentFilter, config: SCStreamConfiguration, url: URL) throws {
    self.url = url
    try? FileManager.default.removeItem(at: url)
    let width = config.width, height = config.height
    writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: max(2_000_000, width * height * 4),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      ],
    ])
    input.expectsMediaDataInRealTime = true
    writer.add(input)
    stream = SCStream(filter: filter, configuration: config, delegate: nil)
    super.init()
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
  }

  func start() async throws {
    try await stream.startCapture()
  }

  /// 스트림을 멈추고 파일을 마무리한다.
  func stop() async throws -> URL {
    try await stream.stopCapture()
    let started: Bool = queue.sync { sessionStarted }
    guard started else {
      writer.cancelWriting()
      throw RecordingError.noFrames
    }
    writer.endSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status == .failed {
      throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "unknown")
    }
    return url
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, sampleBuffer.isValid else { return }
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
          let raw = attachments.first?[.status] as? Int,
          SCFrameStatus(rawValue: raw) == .complete
    else { return }

    if !sessionStarted {
      guard writer.startWriting() else { return }
      writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
      sessionStarted = true
    }
    if writer.status == .writing, input.isReadyForMoreMediaData {
      input.append(sampleBuffer)
    }
  }
}

// MARK: - 녹화 한 번

/// 녹화 요청 하나를 끝까지 진행한다: 스트림 시작 → 카운트다운 알약 → 정지 → (GIF면 변환) → 썸네일.
@MainActor
final class RecordingSession {
  static var current: RecordingSession?

  private let request: RecordRequest
  private let screen: NSScreen
  private let display: SCDisplay
  private let ownApps: [SCRunningApplication]
  private var recorder: ScreenRecorder?
  private var pill: RecordingPill?
  private var continuation: CheckedContinuation<Void, Never>?
  private var timer: Timer?
  private var startedAt = Date()
  private var stopped = false

  init(request: RecordRequest, screen: NSScreen, display: SCDisplay, ownApps: [SCRunningApplication]) {
    self.request = request
    self.screen = screen
    self.display = display
    self.ownApps = ownApps
  }

  /// 일찍 끝내고 싶을 때(알약의 정지 단추, 단축키 한 번 더).
  static func stopCurrent() { current?.finishWaiting() }

  func run() async throws -> CaptureOutcome {
    let scale = screen.backingScaleFactor
    let (filter, config) = makeStream(scale: scale)
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Snapdock", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let stamp = Self.timestamp()
    let mp4 = temp.appendingPathComponent("Snapdock \(stamp).mp4")

    let recorder = try ScreenRecorder(filter: filter, config: config, url: mp4)
    self.recorder = recorder
    try await recorder.start()

    startedAt = Date()
    Self.current = self
    let pill = RecordingPill(screen: screen, onStop: { [weak self] in self?.finishWaiting() })
    self.pill = pill
    pill.show()

    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let elapsed = Date().timeIntervalSince(self.startedAt)
        self.pill?.update(elapsed: min(elapsed, CaptureConfig.maxRecordingSeconds))
        if elapsed >= CaptureConfig.maxRecordingSeconds { self.finishWaiting() }
      }
    }
    await withCheckedContinuation { continuation = $0 }

    timer?.invalidate()
    timer = nil
    pill.close()
    self.pill = nil
    Self.current = nil
    let elapsed = min(Date().timeIntervalSince(startedAt), CaptureConfig.maxRecordingSeconds)

    let file = try await recorder.stop()
    let thumb = try await Self.thumbnail(of: file)

    let finalURL: URL
    switch request.kind {
    case .video:
      finalURL = file
    case .gif:
      let gif = temp.appendingPathComponent("Snapdock \(stamp).gif")
      try await Self.makeGIF(from: file, to: gif)
      try? FileManager.default.removeItem(at: file)
      finalURL = gif
    }
    return CaptureOutcome(
      action: .copy,
      shape: request.window != nil ? .window : .rect,
      png: thumb.png,
      width: thumb.width,
      height: thumb.height,
      kind: request.kind == .video ? .video : .gif,
      path: finalURL.path,
      durationMs: Int((elapsed * 1000).rounded())
    )
  }

  private func finishWaiting() {
    guard !stopped else { return }
    stopped = true
    continuation?.resume()
    continuation = nil
  }

  private func makeStream(scale: CGFloat) -> (SCContentFilter, SCStreamConfiguration) {
    let config = SCStreamConfiguration()
    config.showsCursor = true
    let fps = request.kind == .video ? RecordingLimits.videoFPS : RecordingLimits.gifRecordFPS
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.queueDepth = 6

    let filter: SCContentFilter
    let size: CGSize
    if let window = request.window {
      filter = SCContentFilter(desktopIndependentWindow: window)
      size = window.frame.size
      config.ignoreShadowsSingleWindow = true
    } else {
      filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
      let rect = request.sourceRect ?? CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
      config.sourceRect = rect
      size = rect.size
    }
    // H.264는 짝수 크기를 좋아한다.
    config.width = Int((size.width * scale).rounded()) & ~1
    config.height = Int((size.height * scale).rounded()) & ~1
    return (filter, config)
  }

  private static func timestamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH.mm.ss"
    return f.string(from: Date())
  }

  /// 영상의 가운데쯤 프레임을 썸네일로 쓴다 (첫 프레임은 검을 때가 있다).
  private static func thumbnail(of url: URL) async throws -> (png: Data, width: Int, height: Int) {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 640, height: 640)
    let (image, _) = try await generator.image(at: CMTime(seconds: max(0, min(duration / 2, 1)), preferredTimescale: 600))
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
      throw RecordingError.noFrames
    }
    return (png, image.width, image.height)
  }

  /// MP4를 일정한 간격으로 뽑아 GIF로 만든다. 가로는 [RecordingLimits.gifMaxWidth]로 줄인다.
  private static func makeGIF(from mp4: URL, to gif: URL) async throws {
    let asset = AVURLAsset(url: mp4)
    let duration = try await asset.load(.duration).seconds
    let fps = Double(RecordingLimits.gifFPS)
    let count = max(1, Int(duration * fps))

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: RecordingLimits.gifMaxWidth, height: 10_000)
    let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance

    guard let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, count, nil) else {
      throw RecordingError.writerFailed("gif destination")
    }
    CGImageDestinationSetProperties(destination, [
      kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
    ] as CFDictionary)
    let frameProperties = [
      kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps],
    ] as CFDictionary

    for i in 0..<count {
      let time = CMTime(seconds: min(Double(i) / fps, max(0, duration - 0.01)), preferredTimescale: 600)
      let (image, _) = try await generator.image(at: time)
      CGImageDestinationAddImage(destination, image, frameProperties)
    }
    guard CGImageDestinationFinalize(destination) else { throw RecordingError.writerFailed("gif finalize") }
  }
}

// MARK: - 카운트다운 알약

/// 녹화 중에 화면 위쪽에 떠 있는 작은 알약. 우리 앱의 창이라 캡처에서 빠진다.
@MainActor
private final class RecordingPill {
  private let panel: NSPanel
  private let label = NSTextField(labelWithString: "")
  private let dot = NSView()

  init(screen: NSScreen, onStop: @escaping () -> Void) {
    panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 168, height: 36), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .screenSaver
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false

    let bar = NSVisualEffectView(frame: panel.contentLayoutRect)
    bar.material = .menu
    bar.state = .active
    bar.wantsLayer = true
    bar.layer?.cornerRadius = 18
    bar.layer?.borderWidth = 0.5
    bar.layer?.borderColor = NSColor.separatorColor.cgColor

    dot.wantsLayer = true
    dot.layer?.backgroundColor = NSColor(srgbRed: 0xE2 / 255, green: 0x4B / 255, blue: 0x4A / 255, alpha: 1).cgColor
    dot.layer?.cornerRadius = 4
    let blink = CABasicAnimation(keyPath: "opacity")
    blink.fromValue = 1
    blink.toValue = 0.25
    blink.duration = 0.5
    blink.autoreverses = true
    blink.repeatCount = .infinity
    dot.layer?.add(blink, forKey: "blink")

    label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    let stop = StopButton(onStop: onStop)
    let stack = NSStackView(views: [dot, label, stop])
    stack.orientation = .horizontal
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 6)
    dot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      dot.widthAnchor.constraint(equalToConstant: 8),
      dot.heightAnchor.constraint(equalToConstant: 8),
    ])
    bar.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
      stack.topAnchor.constraint(equalTo: bar.topAnchor),
      stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
    ])
    panel.contentView = bar

    let visible = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(x: visible.midX - 84, y: visible.maxY - 36 - 12))
    update(elapsed: 0)
  }

  func show() { panel.orderFrontRegardless() }

  func close() {
    panel.orderOut(nil)
    panel.contentView = nil
  }

  func update(elapsed: Double) {
    func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    label.stringValue = "\(clock(Int(elapsed))) / \(clock(Int(CaptureConfig.maxRecordingSeconds)))"
  }
}

private final class StopButton: NSButton {
  private let handler: () -> Void

  init(onStop: @escaping () -> Void) {
    handler = onStop
    super.init(frame: .zero)
    image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "정지")?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    isBordered = false
    imagePosition = .imageOnly
    toolTip = "정지"
    target = self
    action = #selector(tapped)
    widthAnchor.constraint(equalToConstant: 28).isActive = true
    heightAnchor.constraint(equalToConstant: 28).isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  @objc private func tapped() { handler() }
}
