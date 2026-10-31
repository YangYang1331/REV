import 'package:obd_dashboard/core/debug_flags.dart';

/// 运行环境配置。
///
/// 参考原版 backend/api_config + core/config/environment 的做法，
/// 但本重新实现版默认离线，不依赖任何服务端激活。
class AppEnvironment {
  AppEnvironment._();

  /// 应用名
  static const String appName = 'OBD 仪表盘';

  /// 版本（与 pubspec.yaml 保持一致，发版时同步修改）
  static const String version = '2.17.5';
  static const int versionCode = 59;

  /// 默认数据源模式：'offline' 离线模拟 / 'ble' 真实蓝牙
  static String defaultDataSource() {
    if (DebugFlags.forceOfflineDemo) return 'offline';
    return 'ble';
  }

  /// 是否允许进入设置里的"离线演示模式"
  static bool get demoModeEnabled => DebugFlags.demoModeEnabled;
}
