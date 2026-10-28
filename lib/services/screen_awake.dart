import 'package:wakelock_plus/wakelock_plus.dart';

/// 保持屏幕常亮（参考原版 services/screen_awake.dart）。
class ScreenAwake {
  ScreenAwake();

  bool _enabled = false;
  bool get enabled => _enabled;

  /// 车机仪表盘场景建议常亮
  Future<void> setEnabled(bool on) async {
    _enabled = on;
    if (on) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }
}
