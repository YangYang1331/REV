import 'dart:typed_data';

import 'game_telemetry.dart';

/// 游戏 UDP 包解析器（纯静态、无 IO、可单测）。
///
/// 所有偏移量为小端字节序，采用各游戏社区公开布局。包长不足或魔数不符时返回 null，
/// 上层静默丢弃坏包。
class GameUdpParser {
  GameUdpParser._();

  /// 按协议解析整包；协议未知返回 null。
  static GameTelemetry? parse(GameProtocol protocol, Uint8List data) {
    try {
      switch (protocol) {
        case GameProtocol.forza:
          return _parseForza(data);
        case GameProtocol.f1:
          return _parseF1(data);
        case GameProtocol.assettoCorsa:
          return _parseAc(data);
        case GameProtocol.beamng:
          return _parseBeamng(data);
        case GameProtocol.ets2:
          return _parseEts2(data);
      }
    } catch (_) {
      // 越界 / NaN 一律按坏包丢弃。
      return null;
    }
  }

  // ── Forza Horizon / Motorsport（小端，社区 FH4/FH5 布局）──
  // 0x00 IsRaceOn s32；0x10 EngineCurrentRpm f32；
  // 0x20/0x24/0x28 速度矢量 m/s；0x43 当前挡 u8。
  static GameTelemetry? _parseForza(Uint8List d) {
    if (d.length < 0x44) return null;
    final bd = ByteData.sublistView(d);
    final rpm = bd.getFloat32(0x10, Endian.little);
    final vx = bd.getFloat32(0x20, Endian.little);
    final vy = bd.getFloat32(0x24, Endian.little);
    final vz = bd.getFloat32(0x28, Endian.little);
    final ms = (vx * vx + vy * vy + vz * vz);
    final speed = ms <= 0 ? 0.0 : _sqrt(ms) * 3.6;
    var gear = d[0x43];
    // Forza 挡位编码：bit0..3 = 前进挡，bit4..6 = 倒挡位。社区约定：
    // 0 = N，1..8 = 挡，15 = R（有些版本 R=0x10）。
    if (gear >= 0x10) gear = 0; // 安全边界
    var g = gear;
    if (gear == 15) g = -1;
    if (!rpm.isFinite) return null;
    return GameTelemetry(
      rpm: rpm < 0 ? 0 : rpm,
      speedKmh: speed < 0 ? 0 : speed,
      gear: g,
    );
  }

  // ── F1 22/23/24（小端）──
  // 24 字节包头：packetId u8 @0x06。CarTelemetry(id=6)：
  // 0x18 speed u16 km/h；0x27 gear i8；0x28 engineRpm u16。
  static GameTelemetry? _parseF1(Uint8List d) {
    if (d.length < 0x2C) return null;
    final bd = ByteData.sublistView(d);
    final packetId = d[0x06];
    // F1 的转速/车速主要在 CarTelemetry(6)；Motion(0) 也带速度但无 rpm。
    // 为容错，无论包类型都按偏移读，读不到就置 0。
    final speed = bd.getUint16(0x18, Endian.little).toDouble(); // km/h
    var rpm = 0.0;
    var gear = 0;
    if (packetId == 6) {
      if (d.length >= 0x2C) {
        rpm = bd.getUint16(0x28, Endian.little).toDouble();
        gear = bd.getInt8(0x27);
      }
    } else {
      // 其它包：rpm 未知，给 0；车速仍可用。
      gear = 0;
    }
    return GameTelemetry(
      rpm: rpm < 0 ? 0 : rpm,
      speedKmh: speed < 0 ? 0 : speed,
      gear: gear,
    );
  }

  // ── Assetto Corsa（小端，physics/out 包）──
  // 0x00 packetId i32；0x04 version i32；0x08 kmh f32；0x0C rpm f32；0x1C gear i32。
  static GameTelemetry? _parseAc(Uint8List d) {
    if (d.length < 0x20) return null;
    final bd = ByteData.sublistView(d);
    final speed = bd.getFloat32(0x08, Endian.little);
    final rpm = bd.getFloat32(0x0C, Endian.little);
    var gear = bd.getInt32(0x1C, Endian.little);
    if (gear < -1) gear = -1;
    if (gear > 15) gear = 15;
    if (!rpm.isFinite) return null;
    return GameTelemetry(
      rpm: rpm < 0 ? 0 : rpm,
      speedKmh: speed.isFinite && speed > 0 ? speed : 0,
      gear: gear,
    );
  }

  // ── BeamNG.outGauge（小端，128 字节）──
  // 0x00 magic "GAUG"；0x04 version i32；0x08 rpm f32；
  // 0x10 speed km/h f32；0x34 gear i32。
  static GameTelemetry? _parseBeamng(Uint8List d) {
    if (d.length < 0x38) return null;
    // 魔数校验（outGauge）。
    if (d[0] != 0x47 || d[1] != 0x41 || d[2] != 0x55 || d[3] != 0x47) {
      return null;
    }
    final bd = ByteData.sublistView(d);
    final rpm = bd.getFloat32(0x08, Endian.little);
    final speed = bd.getFloat32(0x10, Endian.little);
    var gear = bd.getInt32(0x34, Endian.little);
    if (gear < -1) gear = -1;
    if (gear > 15) gear = 15;
    if (!rpm.isFinite) return null;
    return GameTelemetry(
      rpm: rpm < 0 ? 0 : rpm,
      speedKmh: speed.isFinite && speed > 0 ? speed : 0,
      gear: gear,
    );
  }

  // ── ETS2 / ATS（SCS telemetry，尽力解析）──
  // SCS 二进制布局随版本变化大，这里只做最小容错：
  // 该包通常很大，rpm 在 float 段；不做硬偏移猜测，返回空帧（连接即视为在线）。
  static GameTelemetry? _parseEts2(Uint8List d) {
    if (d.length < 32) return null;
    // 不猜偏移（不同插件差异大）；仅标记在线，rpm/speed 由上层置 0。
    // 用户可在后续版本提供具体插件偏移。
    return const GameTelemetry(rpm: 0, speedKmh: 0, gear: 0);
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    double x = v;
    double y = 1.0;
    while ((x - y).abs() > 1e-6) {
      x = (x + y) / 2;
      y = v / x;
    }
    return x;
  }
}
