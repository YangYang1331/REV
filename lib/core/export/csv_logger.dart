/// 实时 PID 导出 CSV（纯逻辑：只负责行格式，不碰 IO，可单测）。
library;

/// 把一帧车辆数据格式化为 CSV 行。字段固定、表头稳定，便于 Excel / 仪表盘回读。
class CsvLogger {
  CsvLogger._();

  static const String header =
      'time_ms,rpm,speed_kmh,coolant_c,voltage_v,gear';

  /// 把可能为 null 的数值格式化为空串（null）而非 "NaN"。
  static String _cell(num? v, [int decimals = 1]) {
    if (v == null) return '';
    if (v.isNaN || v.isInfinite) return '';
    return v is int ? v.toString() : v.toStringAsFixed(decimals);
  }

  /// 构造一行 CSV。[rpm]/[speed]/[gear] 为必有项，其余可空。
  static String row({
    required int timeMs,
    required int rpm,
    required double speedKmh,
    double? coolantC,
    double? voltageV,
    int gear = 0,
  }) {
    return [
      timeMs.toString(),
      rpm.toString(),
      _cell(speedKmh, 1),
      _cell(coolantC, 1),
      _cell(voltageV, 2),
      gear.toString(),
    ].join(',');
  }
}
