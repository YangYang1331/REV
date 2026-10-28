/// 游戏 UDP 遥测：协议注册表与一帧解析结果（纯逻辑，可单测）。
///
/// 这些偏移量来自各游戏 Data Out / Shared Memory 的社区公开布局。
/// 不同游戏大版本（Forza FH4/FH5/FM7/FM2023、F1 22/23/24）布局略有差异，
/// 这里采用最通用的社区布局；解析失败（包长不足/魔数不符）一律返回 null，
/// 由上层静默丢弃，绝不崩。
library;

/// 支持的游戏 UDP 协议。
enum GameProtocol {
  forza(
    id: 'forza',
    label: 'Forza Horizon / Motorsport',
    port: 5300,
    hint: '游戏内：设置 → 遥测数据输出 / Data Out → 开启 UDP，IP 填本机（手机/车机），端口 5300。',
  ),
  f1(
    id: 'f1',
    label: 'F1 22/23/24 · DiRT Rally',
    port: 20777,
    hint: '游戏内：设置 → 遥测 → 开启 UDP，端口 20777，广播 IP 填本机。',
  ),
  assettoCorsa(
    id: 'ac',
    label: 'Assetto Corsa / Competizione',
    port: 9996,
    hint: 'AC：CSP 开启 Shared Memory / UDP out；ACC：遥测设置里开 UDP，端口 9996。',
  ),
  beamng(
    id: 'beamng',
    label: 'BeamNG.drive',
    port: 4564,
    hint: '游戏内：选项 → 其他 → 输出 Gauge / outGauge，端口 4564，IP 填本机。',
  ),
  ets2(
    id: 'ets2',
    label: 'ETS2 / ATS（欧洲卡车模拟）',
    port: 20818,
    hint: '需 SCS Telemetry 插件（scs-sdk）输出 UDP 20818；原厂游戏不直接发 UDP。',
  );

  const GameProtocol({
    required this.id,
    required this.label,
    required this.port,
    required this.hint,
  });

  final String id;
  final String label;
  final int port;
  final String hint;

  static GameProtocol? byId(String id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }

  static GameProtocol? byPort(int port) {
    for (final p in values) {
      if (p.port == port) return p;
    }
    return null;
  }
}

/// 解析后的一帧游戏遥测（单位与 ObdData 对齐：rpm 整数、speed km/h、gear 0=空挡）。
class GameTelemetry {
  const GameTelemetry({
    required this.rpm,
    required this.speedKmh,
    required this.gear,
    this.throttle,
    this.brake,
    this.clutch,
    this.boost,
  });

  /// 发动机转速 rpm。
  final double rpm;

  /// 车速 km/h。
  final double speedKmh;

  /// 档位：0 = 空挡，-1 = 倒挡，1..N = 前进挡。
  final int gear;

  /// 油门 0..1（可能为 null）。
  final double? throttle;

  /// 刹车 0..1。
  final double? brake;

  /// 离合 0..1。
  final double? clutch;

  /// 增压 bar。
  final double? boost;

  static const GameTelemetry empty =
      GameTelemetry(rpm: 0, speedKmh: 0, gear: 0);

  bool get isUsable => rpm >= 0 && speedKmh >= 0;
}
