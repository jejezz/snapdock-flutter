import Cocoa
import FlutterMacOS

/// Flutter와 네이티브 캡처를 잇는 MethodChannel.
///
///   permissionStatus   -> Bool        화면 기록 권한이 있는가
///   requestPermission  -> Bool        시스템 권한 요청을 띄운다
///   openPermissionSettings            시스템 설정의 화면 기록 항목을 연다
///   captureRegion {shape}  -> Map?    영역을 고르게 한다. 취소하면 null
///   copyImage {png}                   PNG를 클립보드에 넣는다
enum CaptureChannel {
  static let name = "art.zoomon.snapdock/capture"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "permissionStatus":
        result(CGPreflightScreenCaptureAccess())
      case "requestPermission":
        result(CGRequestScreenCaptureAccess())
      case "openPermissionSettings":
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "captureRegion":
        let args = call.arguments as? [String: Any]
        let shape = CaptureShape(rawValue: args?["shape"] as? String ?? "") ?? .rect
        Task { @MainActor in
          CaptureOverlayController.shared.run(shape: shape) { outcome in
            respond(outcome, to: result)
          }
        }
      case "stopRecording":
        Task { @MainActor in RecordingSession.stopCurrent() }
        result(nil)
      case "openFolder":
        let kind = (call.arguments as? [String: Any])?["kind"] as? String
        openSaveFolder(movies: kind == "movies")
        result(nil)
      case "copyFile":
        guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "path is required", details: nil))
          return
        }
        copyFileToPasteboard(path)
        result(nil)
      case "saveImage":
        guard let png = ((call.arguments as? [String: Any])?["png"] as? FlutterStandardTypedData)?.data else {
          result(FlutterError(code: "bad_args", message: "png is required", details: nil))
          return
        }
        result(savePNG(png))
      case "saveFile":
        guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "path is required", details: nil))
          return
        }
        result(saveFile(path))
      case "copyImage":
        guard let args = call.arguments as? [String: Any], let png = (args["png"] as? FlutterStandardTypedData)?.data else {
          result(FlutterError(code: "bad_args", message: "png is required", details: nil))
          return
        }
        copyToPasteboard(png)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func respond(_ outcome: Result<CaptureOutcome?, Error>, to result: FlutterResult) {
    switch outcome {
    case .failure(let error):
      if case CaptureError.permissionDenied = error {
        result(FlutterError(code: "permission_denied", message: "Screen recording permission is required", details: nil))
      } else {
        result(FlutterError(code: "capture_failed", message: "\(error)", details: nil))
      }
    case .success(nil):
      result(nil)
    case .success(let outcome?):
      var map: [String: Any] = [
        "action": outcome.action.rawValue,
        "shape": outcome.shape.rawValue,
        "kind": outcome.kind.rawValue,
        "png": FlutterStandardTypedData(bytes: outcome.png),
        "width": outcome.width,
        "height": outcome.height,
      ]
      if outcome.kind == .image {
        switch outcome.action {
        case .copy:
          copyToPasteboard(outcome.png)
        case .save:
          if let path = savePNG(outcome.png) { map["path"] = path }
        }
      } else {
        map["path"] = outcome.path
        map["durationMs"] = outcome.durationMs
      }
      result(map)
    }
  }

  private static func copyToPasteboard(_ png: Data) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setData(png, forType: .png)
  }

  /// ~/Pictures/Snapdock 또는 ~/Movies/Snapdock을 Finder로 연다. 아직 없으면 만든다.
  private static func openSaveFolder(movies: Bool) {
    let base: FileManager.SearchPathDirectory = movies ? .moviesDirectory : .picturesDirectory
    guard let root = FileManager.default.urls(for: base, in: .userDomainMask).first else { return }
    let folder = root.appendingPathComponent("Snapdock", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(folder)
  }

  /// 영상·GIF는 파일 자체를 클립보드에 올린다. Finder나 메신저에 붙여 넣으면 파일로 들어간다.
  private static func copyFileToPasteboard(_ path: String) {
    let url = URL(fileURLWithPath: path)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([url as NSURL])
    if url.pathExtension.lowercased() == "gif", let data = try? Data(contentsOf: url) {
      pb.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
    }
  }

  /// 임시 폴더의 녹화 파일을 사용자 폴더로 옮겨 둔다. 영상은 ~/Movies/Snapdock, GIF는 ~/Pictures/Snapdock.
  private static func saveFile(_ path: String) -> String? {
    let source = URL(fileURLWithPath: path)
    let isGIF = source.pathExtension.lowercased() == "gif"
    let base: FileManager.SearchPathDirectory = isGIF ? .picturesDirectory : .moviesDirectory
    guard let root = FileManager.default.urls(for: base, in: .userDomainMask).first else { return nil }
    let folder = root.appendingPathComponent("Snapdock", isDirectory: true)
    let target = folder.appendingPathComponent(source.lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
      try FileManager.default.copyItem(at: source, to: target)
      return target.path
    } catch {
      return nil
    }
  }

  /// ~/Pictures/Snapdock 아래에 `Snapdock 2026-10-21 14.03.05.png` 형태로 저장한다.
  private static func savePNG(_ png: Data) -> String? {
    guard let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else { return nil }
    let folder = pictures.appendingPathComponent("Snapdock", isDirectory: true)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let file = folder.appendingPathComponent("Snapdock \(formatter.string(from: Date())).png")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try png.write(to: file, options: .atomic)
      return file.path
    } catch {
      return nil
    }
  }
}
