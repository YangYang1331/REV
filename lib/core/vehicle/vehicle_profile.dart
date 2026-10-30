/// 车型档案：协议、红区、档位、电压范围、变速箱速比、告警阈值。
///
/// 档位反推原理（标准 OBD 不直接给档位）：某一档下
///   K = rpm / speed(km/h) = (档齿比 × 主减) × 60 / (轮胎周长m × 3.6)
/// 实测 K 落在哪一档区间就是哪一档。
class VehicleProfile {
  const VehicleProfile({
    required this.id,
    required this.name,
    required this.protocol,
    required this.redlineRpm,
    required this.maxGear,
    required this.cylinders,
    required this.fuel,
    this.displacementL = 2.0,
    this.voltMin = 12.5,
    this.voltMax = 14.7,
    this.gearRatios = const <double>[],
    this.finalDrive = 4.10,
    this.tireCircumferenceM = 2.00,
    this.shiftUpRpm = 3200,
    this.shiftDownRpm = 1300,
    this.idleRpm = 800,
    this.coolantWarn = 105,
    this.coolantDanger = 115,
    this.rpmDangerFactor = 0.985,
    this.note = '',
  });

  final String id;
  final String name;
  final int protocol; // 0=自动, 6=CAN11 500k, 7=CAN29, 3=ISO9141, 4/5=KWP
  final int redlineRpm;
  final int maxGear;
  final int cylinders;
  final String fuel;
  final double displacementL;
  final double voltMin;
  final double voltMax;
  final List<double> gearRatios;
  final double finalDrive;
  final double tireCircumferenceM;
  final int shiftUpRpm;
  final int shiftDownRpm;
  final int idleRpm;
  final int coolantWarn;
  final int coolantDanger;
  final double rpmDangerFactor;
  final String note;

  int get rpmDanger => (redlineRpm * rpmDangerFactor).round();

  /// 由转速 + 车速反推档位。
  /// 0=空档/静止/离合，1..maxGear=档位，-1=无法判断。
  ///
  /// [prevGear] 为上一帧档位，用于迟滞：液力变矩器滑移、坡道加减速会让
  /// K 在相邻两档间抖动，若本档仍在放宽容差内就不跳挡（声浪"闷音"逻辑
  /// 依赖档位，跳变会听出来）。
  int estimateGear(double rpm, double speedKmh, {int? prevGear}) {
    if (speedKmh < 3) return 0;
    if (rpm < idleRpm * 0.7) return 0;
    if (gearRatios.isEmpty) {
      final top = maxGear * 38.0;
      final g = (speedKmh / top * maxGear).round().clamp(1, maxGear);
      return g;
    }
    final k = rpm / speedKmh;
    final kt = gearKTable();
    double errOf(int i) => (k - kt[i]).abs() / kt[i];
    // 低速（1 挡）带液力变矩器滑移，K 偏大，容差放宽
    double tolOf(int i) => i == 0 ? 0.42 : 0.24;

    int best = -1;
    double bestErr = double.maxFinite;
    for (var i = 0; i < kt.length; i++) {
      final err = errOf(i);
      if (err < tolOf(i) && err < bestErr) {
        bestErr = err;
        best = i + 1;
      }
    }
    // 迟滞：上一档仍明显成立时保持，避免相邻档来回跳。
    if (prevGear != null && prevGear >= 1 && prevGear <= kt.length) {
      final pe = errOf(prevGear - 1);
      final plausible = pe < tolOf(prevGear - 1) * 1.25;
      final competitive = best < 0 || pe < bestErr * 2.0 || pe < 0.05;
      if (plausible && competitive) return prevGear;
    }
    if (best < 0) {
      var bi = 0;
      var be = double.maxFinite;
      for (var i = 0; i < kt.length; i++) {
        final e = (k - kt[i]).abs();
        if (e < be) {
          be = e;
          bi = i;
        }
      }
      best = bi + 1;
    }
    return best.clamp(1, maxGear);
  }

  /// 每一档 K = rpm / speed
  List<double> gearKTable() {
    final f = 60.0 / (tireCircumferenceM * 3.6);
    return gearRatios.map((g) => g * finalDrive * f).toList();
  }

  /// 给定档位与转速求理论车速
  double speedForRpm(int gear1based, double rpm) {
    if (gear1based < 1 || gearRatios.isEmpty) return rpm / 1000.0 * 30.0;
    final k = gearRatios[gear1based - 1] * finalDrive * 60.0 /
        (tireCircumferenceM * 3.6);
    return k <= 0 ? 0 : rpm / k;
  }

  /// 给定档位与车速求理论转速
  double rpmForSpeed(int gear1based, double speedKmh) {
    if (gear1based < 1 || gearRatios.isEmpty) {
      return idleRpm + speedKmh * 55.0;
    }
    final k = gearRatios[gear1based - 1] * finalDrive * 60.0 /
        (tireCircumferenceM * 3.6);
    return speedKmh * k;
  }

  /// 马自达 6（2004–2013，含 2011 款"普马"）2.0L 5AT 齿比：
  /// 3.620 / 1.925 / 1.285 / 0.933 / 0.692，主减 4.147。
  /// 校核锚点：5 挡 120 km/h ≈ 2800–2900 rpm、140 km/h ≈ 3400 rpm
  /// （实测 K=24.3，本表 K5=24.1，误差 <1%）。
  static const List<double> _mazda6Ratios = [
    3.620, 1.925, 1.285, 0.933, 0.692
  ];

  /// 创驰蓝天 6AT（SKYACTIV-Drive）齿比：3.552 / 2.022 / 1.452 / 1.000 /
  /// 0.708 / 0.599，2.0L 主减速比 4.325。
  static const List<double> _skyactiv6AtRatios = [
    3.552, 2.022, 1.452, 1.000, 0.708, 0.599
  ];

  static final List<VehicleProfile> presets = [
    VehicleProfile(
      id: 'mazda6_2011',
      name: '马自达6 2011款 2.0L 自动（LF·5AT）',
      protocol: 6,
      redlineRpm: 6500,
      maxGear: 5,
      cylinders: 4,
      fuel: '汽油',
      displacementL: 2.0,
      gearRatios: _mazda6Ratios,
      finalDrive: 4.147,
      tireCircumferenceM: 1.985,
      shiftUpRpm: 3000,
      shiftDownRpm: 1250,
      idleRpm: 800,
      note: 'ISO15765 CAN 11bit/500k；5AT 齿比 3.620/1.925/1.285/0.933/0.692、'
          '主减 4.147、原厂 205/55R16，档位按 K=转速/车速 反推。',
    ),
    VehicleProfile(
      id: 'mazda6_gj',
      name: '马自达6 2014+ 2.0L 创驰蓝天（6AT）',
      protocol: 6,
      redlineRpm: 6800,
      maxGear: 6,
      cylinders: 4,
      fuel: '汽油',
      displacementL: 2.0,
      gearRatios: _skyactiv6AtRatios,
      finalDrive: 4.325,
      tireCircumferenceM: 2.13,
      shiftUpRpm: 3200,
      shiftDownRpm: 1300,
      idleRpm: 650,
      note: 'SKYACTIV-Drive 6AT（2.0L 主减 4.325，225/55R17 胎周 2.13m）；'
          '若换过大轮毂或胎规格不同，档位会整体偏高/偏低一档。',
    ),
    VehicleProfile(
      id: 'auto',
      name: '通用自动探测（任意 OBD-II）',
      protocol: 0,
      redlineRpm: 6500,
      maxGear: 8,
      cylinders: 4,
      fuel: '汽油',
      note: '自动协商协议，探测 ECU 支持的 PID；档位按车速分段估算',
    ),
    VehicleProfile(
      id: 'toyota',
      name: '丰田 / 雷克萨斯',
      protocol: 6,
      redlineRpm: 6500,
      maxGear: 8,
      cylinders: 4,
      fuel: '汽油',
    ),
    VehicleProfile(
      id: 'honda',
      name: '本田',
      protocol: 6,
      redlineRpm: 6800,
      maxGear: 6,
      cylinders: 4,
      fuel: '汽油',
    ),
    VehicleProfile(
      id: 'vw',
      name: '大众 / 奥迪 / 斯柯达',
      protocol: 6,
      redlineRpm: 6500,
      maxGear: 7,
      cylinders: 4,
      fuel: '汽油',
      voltMin: 12.4,
    ),
    VehicleProfile(
      id: 'nissan',
      name: '日产 / 英菲尼迪',
      protocol: 6,
      redlineRpm: 6500,
      maxGear: 7,
      cylinders: 4,
      fuel: '汽油',
    ),
    VehicleProfile(
      id: 'ford',
      name: '福特 / 林肯',
      protocol: 6,
      redlineRpm: 6500,
      maxGear: 6,
      cylinders: 4,
      fuel: '汽油',
    ),
    VehicleProfile(
      id: 'gm',
      name: '通用 / 别克 / 雪佛兰',
      protocol: 6,
      redlineRpm: 6500,
      maxGear: 6,
      cylinders: 4,
      fuel: '汽油',
      voltMin: 12.6,
    ),
    VehicleProfile(
      id: 'byd',
      name: '比亚迪 / 国产（CAN）',
      protocol: 6,
      redlineRpm: 6500,
      maxGear: 7,
      cylinders: 4,
      fuel: '汽油',
      voltMin: 12.4,
    ),
    VehicleProfile(
      id: 'iso9141',
      name: '老车 ISO 9141 / KWP（约2006前）',
      protocol: 3,
      redlineRpm: 6000,
      maxGear: 5,
      cylinders: 4,
      fuel: '汽油',
      voltMin: 12.3,
    ),
    VehicleProfile(
      id: 'game',
      name: '电脑游戏 / 模拟器（UDP 遥测）',
      protocol: 0,
      redlineRpm: 7000,
      maxGear: 8,
      cylinders: 4,
      fuel: '汽油',
      voltMin: 12.0,
      voltMax: 15.0,
      note: '档位/转速/车速由游戏直接下发，无需 OBD',
    ),
  ];

  static VehicleProfile byId(String id) =>
      presets.firstWhere((p) => p.id == id, orElse: () => presets[1]);
}
