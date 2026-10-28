import 'dart:math' as math;

/// 派生量计算（SAE J1979 口径 + 经典速度密度法），全部公开物理公式。
class FuelCalc {
  /// 速度密度法（Speed-Density）估算空气流量，用于没有 MAF（PID 0x10）的车：
  ///
  ///   m_air(kg/s) = MAP(Pa) · Vd(m³) · (rpm/2/60) · VE / (R_spec · T(K))
  ///
  /// 四冲程每两转一个循环（rpm/2），R_spec=287.05。化简为 g/s：
  ///   maf = MAP(kPa) · Vd(L) · rpm · VE · 1000 / (120 · 287.05 · T(K))
  ///
  /// [ve] 容积效率，自然吸气取 ~0.85。
  static double? mafFromMap(
    double? mapKpa,
    double rpm,
    double? intakeTempC,
    double dispL, {
    double ve = 0.85,
  }) {
    if (mapKpa == null || mapKpa <= 0 || rpm <= 0 || dispL <= 0) return null;
    final tk = (intakeTempC == null ? 30.0 : intakeTempC) + 273.15;
    final gps = mapKpa * dispL * rpm * ve * 1000.0 / (120.0 * 287.05 * tk);
    return math.max(0.0, gps);
  }

  /// 由进气压力反算海拔（标准大气压 101.325 kPa，约每 100m 降 1.2kPa）
  static double? altitudeFromMap(double? mapKpa) {
    if (mapKpa == null) return null;
    return (101.325 - mapKpa) * 8.42;
  }
}
