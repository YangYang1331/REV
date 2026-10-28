/// 调试旗标（参考原版 core/debug_flags.dart）。
/// 所有开关集中在首屏设置页，方便离线调试。
class DebugFlags {
  DebugFlags._();

  /// 强制使用离线模拟数据源（不连蓝牙也能跑）
  static bool forceOfflineDemo = false;

  /// 允许在设置页切换到离线演示模式
  static bool demoModeEnabled = true;

  /// 打印 OBD 收发日志
  static bool logObdTraffic = true;
}
