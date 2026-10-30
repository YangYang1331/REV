/// 马力/扭矩估算（纯逻辑、可单测）。
///
/// 基于牛顿第二定律：轮上功率 = 质量 × 纵向加速度 × 车速，再扣除空气阻力。
/// 结果为"估算"区间（给定 ±不确定带），明确标注，不是实测马力机数据。
library;

class DynoEstimate {
  const DynoEstimate({
    required this.wheelHp,
    required this.crankHp,
    required this.torqueNm,
    required this.crankHpLow,
    required this.crankHpHigh,
  });

  /// 轮上马力 hp。
  final double wheelHp;

  /// 曲轴（发动机）估算马力 = 轮上 / 传动效率。
  final double crankHp;

  /// 曲轴扭矩 N·m（按当前转速）。
  final double torqueNm;

  /// 估算下限/上限（曲轴）。
  final double crankHpLow;
  final double crankHpHigh;
}

class DynoInputs {
  const DynoInputs({
    required this.massKg,
    required this.drivetrainEfficiency,
    this.dragAreaM2 = 0.7, // 迎风 Cd×A，普通轿车约 0.6~0.8
    this.uncertainty = 0.15, // ±15% 不确定带
  });

  /// 整车质量 kg（车重+人）。
  final double massKg;

  /// 传动效率（前驱 0.85、后驱 0.82、四驱 0.75、手动 0.9）。
  final double drivetrainEfficiency;

  /// 迎风面积 Cd·A（m²）。
  final double dragAreaM2;

  /// 估算不确定带（±比例）。
  final double uncertainty;
}

class DynoEstimator {
  DynoEstimator._();

  static const double _rho = 1.225; // 空气密度 kg/m³
  static const double _hp = 745.7; // 1 hp = 745.7 W

  /// [accelMss] 纵向加速度 m/s²（减速为负，取正驱动段）。
  /// [speedMps] 车速 m/s。[rpm] 当前转速（用于扭矩换算）。
  static DynoEstimate estimate(
    DynoInputs inp,
    double accelMss,
    double speedMps,
    double rpm,
  ) {
    final accel = accelMss < 0 ? 0.0 : accelMss;
    final v = speedMps < 0 ? 0.0 : speedMps;

    // 加速力 = m·a
    final forceAccel = inp.massKg * accel;
    // 空气阻力
    final forceDrag = 0.5 * _rho * inp.dragAreaM2 * v * v;
    final wheelForce = (forceAccel - forceDrag) < 0 ? 0.0 : forceAccel - forceDrag;

    // 轮上功率 W
    final wheelW = wheelForce * v;
    final wheelHp = wheelW / _hp;
    final eff = inp.drivetrainEfficiency.clamp(0.5, 1.0);
    final crankHp = eff <= 0 ? wheelHp : wheelHp / eff;

    // 扭矩：P(W) = T·ω，ω = rpm·2π/60
    double torqueNm = 0;
    if (rpm > 500) {
      final omega = rpm * 2 * 3.14159265 / 60.0;
      final crankW = crankHp * _hp;
      torqueNm = crankW / omega;
    }

    final band = crankHp * inp.uncertainty;
    return DynoEstimate(
      wheelHp: wheelHp,
      crankHp: crankHp,
      torqueNm: torqueNm,
      crankHpLow: crankHp - band,
      crankHpHigh: crankHp + band,
    );
  }
}
