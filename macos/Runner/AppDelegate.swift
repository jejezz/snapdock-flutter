import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 트레이로 숨기기가 켜져 있으면 창을 숨겨도(보이는 창이 0개여도) 종료하지 않는다.
    // shared_preferences는 키 앞에 "flutter."를 붙여 UserDefaults에 저장한다.
    return !UserDefaults.standard.bool(forKey: "flutter.hide_in_tray")
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
