import 'package:flutter/foundation.dart';

/// 디버그 빌드 전용: README 데모 러너가 화면 상태를 바꾸는 손잡이.
/// `HomeScreen`이 디버그 빌드에서만 채워 넣고, 릴리스에서는 늘 비어 있다.
abstract final class DemoHooks {
  static VoidCallback? cycleDockSize;
  static VoidCallback? toggleCollapsed;
}
