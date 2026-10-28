/// 仪表盘方向（参考原版 core/skin/dashboard_orientation.dart）。
enum DashboardOrientation {
  landscape,
  portrait,
}

extension DashboardOrientationX on DashboardOrientation {
  String get label => this == DashboardOrientation.landscape ? '横屏' : '竖屏';
}
