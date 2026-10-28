import 'dart:math' as math;

/// 一帧车辆数据。
/// 单位：rpm 转/分；speed km/h；温度 °C；voltage V；
/// map kPa（进气歧管绝对压力）；boost bar（相对压力）；
/// load/throttle/fuelLevel %；maf g/s；
/// 油耗 fuelLph（L/h）、fuelL100（L/100km）；
/// 行程 tripKm/tripFuel/tripSec 本机累计。
///
/// 无标准 PID 的量用 null 表示“不支持/无数据”，由 UI 按支持度分级隐藏，
/// 避免演示模式满屏、实车一插满屏 “--” 的落差。
class ObdData {
  const ObdData({
    this.connected = false,
    this.dataLost = false,
    this.source = 'obd',
    this.rpm = 0,
    this.speed = 0,
    this.coolant,
    this.oilTemp,
    this.intakeTemp,
    this.ambient,
    this.voltage,
    this.map,
    this.maf,
    this.atfTemp,
    this.catTemp,
    this.fuelRailP,
    this.ignAdv,
    this.torque,
    this.ltft,
    this.absLoad,
    this.altitude,
    this.load,
    this.throttle,
    this.fuelLevel,
    this.gear = 0,
    this.heading,
    this.speedAccuracy,
    this.accelG,
    this.tripKm = 0,
    this.tripFuel = 0,
    this.tripSec = 0,
    this.timestamp = 0,
  });

  final bool connected;
  final bool dataLost;
  final String source; // obd / demo / game

  final int rpm;
  final double speed;
  final double? coolant;
  final double? oilTemp;
  final double? intakeTemp;
  final double? ambient;
  final double? voltage;
  final double? map;
  final double? maf;

  // 扩展数据流（无标准 PID 时为 null）
  final double? atfTemp;
  final double? catTemp;
  final double? fuelRailP;
  final double? ignAdv;
  final double? torque;
  final double? ltft;
  final double? absLoad;
  final double? altitude;

  final double? load;
  final double? throttle;
  final double? fuelLevel;

  /// 档位：0=N/静止/离合，1..N=档位，-1=未知
  final int gear;

  /// GPS 模式专有（其余源为 null）：航向角°、速度精度 m、纵向 G 值（带符号）。
  final double? heading;
  final double? speedAccuracy;
  final double? accelG;

  // 行程
  final double tripKm;
  final double tripFuel;
  final double tripSec;
  final int timestamp;

  /// 增压（bar，相对大气压）；无 MAP 时为 null
  double? get boost {
    if (map == null) return null;
    return (map! - 101.3) / 100.0;
  }

  /// 小时油耗 L/h（怠速也成立）；maf(g/s) → L/h 系数 0.3401
  /// （空燃比 14.7、汽油密度 0.720 kg/L：maf/14.7*3600/720）
  double? get fuelLph {
    if (maf == null || maf! <= 0) return null;
    return maf! * 0.3401;
  }

  /// 瞬时油耗 L/100km；车速 <5 km/h 时无意义（用 L/h）
  double? get fuelL100 {
    final lph = fuelLph;
    if (lph == null || speed < 5) return null;
    return lph * 100.0 / speed;
  }

  /// 平均油耗 L/100km（行程）
  double? get tripL100 {
    if (tripKm <= 0.05) return null;
    return tripFuel / tripKm * 100.0;
  }

  /// 平均车速 km/h
  double get tripAvgSpeed =>
      tripSec > 0 ? tripKm / (tripSec / 3600.0) : 0.0;

  bool get isDemo => source == 'demo';

  /// GPS 模式：转速/档位/纵向 G 为按齿比反推的估算值，需在界面上标「估算/虚拟」。
  bool get isGpsEstimated => source == 'gps';

  /// 是否把「无数据源」的 OBD 专有项（水温/电压/油温/进气/MAP/MAF/增压/负荷/
  /// 油门/油位）显示为 "--"，而不是直接隐藏：
  ///  - demo：演示要填满面板；
  ///  - gps：根本没接 ECU，明确显示 "--" 表示这些项无数据源（绝不灌假数据）；
  ///  - real：按 ECU 实际支持度隐藏不支持的 PID（避免实车一接满屏 "--" 的落差）。
  bool get showUnsupportedAsDashes => isDemo || isGpsEstimated;

  ObdData copyWith({
    bool? connected,
    bool? dataLost,
    String? source,
    int? rpm,
    double? speed,
    double? coolant,
    double? oilTemp,
    double? intakeTemp,
    double? ambient,
    double? voltage,
    double? map,
    double? maf,
    double? atfTemp,
    double? catTemp,
    double? fuelRailP,
    double? ignAdv,
    double? torque,
    double? ltft,
    double? absLoad,
    double? altitude,
    double? load,
    double? throttle,
    double? fuelLevel,
    int? gear,
    double? heading,
    double? speedAccuracy,
    double? accelG,
    double? tripKm,
    double? tripFuel,
    double? tripSec,
    int? timestamp,
  }) {
    return ObdData(
      connected: connected ?? this.connected,
      dataLost: dataLost ?? this.dataLost,
      source: source ?? this.source,
      rpm: rpm ?? this.rpm,
      speed: speed ?? this.speed,
      coolant: coolant ?? this.coolant,
      oilTemp: oilTemp ?? this.oilTemp,
      intakeTemp: intakeTemp ?? this.intakeTemp,
      ambient: ambient ?? this.ambient,
      voltage: voltage ?? this.voltage,
      map: map ?? this.map,
      maf: maf ?? this.maf,
      atfTemp: atfTemp ?? this.atfTemp,
      catTemp: catTemp ?? this.catTemp,
      fuelRailP: fuelRailP ?? this.fuelRailP,
      ignAdv: ignAdv ?? this.ignAdv,
      torque: torque ?? this.torque,
      ltft: ltft ?? this.ltft,
      absLoad: absLoad ?? this.absLoad,
      altitude: altitude ?? this.altitude,
      load: load ?? this.load,
      throttle: throttle ?? this.throttle,
      fuelLevel: fuelLevel ?? this.fuelLevel,
      gear: gear ?? this.gear,
      heading: heading ?? this.heading,
      speedAccuracy: speedAccuracy ?? this.speedAccuracy,
      accelG: accelG ?? this.accelG,
      tripKm: tripKm ?? this.tripKm,
      tripFuel: tripFuel ?? this.tripFuel,
      tripSec: tripSec ?? this.tripSec,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// 数据丢失时的安全归零（参考“2s 无有效 PID：归零 rpm/fuel、清空负荷/油门”）
  ObdData zeroedForDataLost() {
    return ObdData(
      connected: connected,
      dataLost: true,
      source: source,
      speed: speed,
      coolant: coolant,
      oilTemp: oilTemp,
      intakeTemp: intakeTemp,
      ambient: ambient,
      voltage: voltage,
      map: map,
      fuelLevel: fuelLevel,
      atfTemp: atfTemp,
      catTemp: catTemp,
      fuelRailP: fuelRailP,
      altitude: altitude,
      gear: 0,
      tripKm: tripKm,
      tripFuel: tripFuel,
      tripSec: tripSec,
      timestamp: timestamp,
    );
  }

  static const ObdData empty = ObdData();
}

double clampDouble(double v, double lo, double hi) =>
    math.min(math.max(v, lo), hi);
