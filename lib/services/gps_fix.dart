/// 最近一次 GPS 定位（全局单点，避免 telemetry ↔ cloud 之间循环依赖）。
///
/// 定位流本身仍由 [CloudService] 按隐私授权决定是否开启；这里只是把"已授权
/// 且正在定位"时拿到的坐标共享给行程记录用。用户关闭位置授权时该值保持 null，
/// 行程里就不会出现轨迹点（本地也不存）。
class GpsFix {
  const GpsFix({required this.lat, required this.lng, this.speedKmh = 0});
  final double lat;
  final double lng;
  final double speedKmh;
}

class GpsFixBus {
  GpsFixBus._();

  /// 最新定位；null = 当前没有可用的定位（未授权 / 未开始 / 已停用）。
  static GpsFix? last;

  static void clear() => last = null;
}
