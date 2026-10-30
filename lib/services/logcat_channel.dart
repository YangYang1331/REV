import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:obd_dashboard/core/game/game_telemetry.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';

/// 车机直连数据通道（免插 OBD）：尝试读取 Android logcat 中车机厂商 CAN 服务
/// 打印的转速/油门行。
///
/// ⚠️ 限制（如实说明）：
///  - 普通第三方应用在 Android 4.1+ 【无法】读取系统/其它 App 的 logcat
///    （需要 READ_LOGS 权限 + ADB 授权或系统签名车机）。
///  - 本通道保留开关：在已 root / ADB 授权 / 系统签名的车机上可用；
///    在普通手机上只能读到本应用自己的日志（几乎无车辆数据）。
///  - 与 OBD 通道并存可切换；读不到就静默空帧，绝不报错崩。
class LogcatChannel {
  LogcatChannel({TelemetryService? telemetry}) : _telemetry = telemetry;

  final TelemetryService? _telemetry;
  Process? _proc;
  StreamSubscription? _sub;
  bool _running = false;
  bool get isRunning => _running;

  /// 最近一次探测到的权限/能力状态，供 UI 如实展示。
  String statusNote = '未启动';

  /// 尝试启动 logcat 读取。返回是否真的读到了外部日志（普通 App 多半 false）。
  Future<bool> start() async {
    await stop();
    try {
      final probe = await Process.run('logcat', ['-d', '-t', '5']);
      final stdout = probe.stdout as String;
      // 能读到系统 tag（如 ActivityManager / SurfaceFlinger）说明有权限读外部日志。
      final canReadSystem = stdout.contains('ActivityManager') ||
          stdout.contains('SurfaceFlinger') ||
          stdout.contains('system_server');
      statusNote = canReadSystem
          ? '已获 logcat 读取权限（车机/ADB 环境），正在监听厂商 CAN 行'
          : '仅能读到本应用日志（普通 App 无法读系统 logcat）：需 ADB/系统签名';
      if (!canReadSystem) return false;

      _proc = await Process.start('logcat', []);
      _running = true;
      _sub = _proc!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_parseLine, onError: (e) {
        debugPrint('logcat listen error: $e');
        stop();
      });
      return true;
    } catch (e) {
      statusNote = 'logcat 不可用：$e（普通应用通常无法读取）';
      return false;
    }
  }

  /// 解析一行 logcat，匹配厂商 CAN 打印的 RPM/车速。纯静态可单测。
  /// 匹配形如 "RPM=3200" / "rpm: 1200" / "speed: 45 kmh" / "gear=3"。
  static ParsedLogLine? parseLine(String line) {
    final rpmMatch =
        RegExp(r'(?:rpm|RPM)[=:\s]+(\d{2,5})').firstMatch(line);
    final speedMatch = RegExp(
            r'(?:speed|kmh|km/h)[=:\s]+(\d{1,3}(?:\.\d+)?)',
            caseSensitive: false)
        .firstMatch(line);
    final gearMatch =
        RegExp(r'(?:gear|挡)[=:\s]?(-?\d{1,2})').firstMatch(line);
    if (rpmMatch == null && speedMatch == null) return null;
    return ParsedLogLine(
      rpm: rpmMatch == null ? null : int.tryParse(rpmMatch.group(1)!),
      speedKmh: speedMatch == null
          ? null
          : double.tryParse(speedMatch.group(1)!),
      gear: gearMatch == null ? null : int.tryParse(gearMatch.group(1)!),
    );
  }

  void _parseLine(String line) {
    final p = parseLine(line);
    if (p == null) return;
    try {
      _telemetry?.onGameFrame(GameTelemetry(
        rpm: (p.rpm ?? 0).toDouble(),
        speedKmh: p.speedKmh ?? 0,
        gear: p.gear ?? 0,
      ));
    } catch (_) {}
  }

  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    _proc?.kill();
    _proc = null;
    statusNote = '已停止';
  }
}

/// logcat 解析结果。
class ParsedLogLine {
  const ParsedLogLine({this.rpm, this.speedKmh, this.gear});
  final int? rpm;
  final double? speedKmh;
  final int? gear;
}
