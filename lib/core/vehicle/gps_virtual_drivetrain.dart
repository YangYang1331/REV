import 'dart:math' as math;

import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';

/// GPS 快乐表：在没有 OBD 转速/档位信号时，按车型齿比由 GPS 车速反推
/// 当前档位与虚拟转速。纯 Dart、无平台依赖，便于单测。
///
/// 原理：对每个档位 g，理论转速 rpm_g(v) = v · k_g，k_g 随档位升高而减小。
/// 选档 = 找到"升档线以下、降档线以上"的档位：
///   - 从 1 档起，若该档 rpm 已超过升档线则升档；
///   - 若已在高档、rpm 跌破降档线则降档；
///   - 加迟滞带宽，避免临界车速反复跳档；
///   - 静止（<3km/h）回空档，转速回到怠速。
class GpsVirtualDrivetrain {
  GpsVirtualDrivetrain(this._profile);

  final VehicleProfile _profile;
  int _gear = 0;

  /// 当前虚拟档位（0=空档/静止）。
  int get gear => _gear;

  /// 由车速反推档位并返回虚拟转速。
  /// [speedKmh] 已校准的 GPS 车速。
  /// 返回虚拟 rpm（已夹在怠速~红区之间）。
  double update(double speedKmh) {
    final ratios = _profile.gearRatios;
    if (ratios.isEmpty || _profile.maxGear < 1) {
      // 无齿比档案：给一个随车速线性爬升的占位转速，绝不超红区。
      _gear = 0;
      return math.min(
          _profile.idleRpm + speedKmh * 55.0, _profile.redlineRpm * 0.95);
    }

    // 静止回空档
    if (speedKmh < 3) {
      _gear = 0;
      return _profile.idleRpm.toDouble();
    }

    final up = _profile.shiftUpRpm + 150; // 升档迟滞带宽
    final down = _profile.shiftDownRpm - 100; // 降档迟滞带宽

    // 目标档：最小的 g，使 rpm_g(v) <= 升档线；若全部超限则顶档。
    var target = 1;
    for (var g = 1; g <= _profile.maxGear; g++) {
      final rpm = _profile.rpmForSpeed(g, speedKmh);
      if (rpm <= up) {
        target = g;
        break;
      }
      target = g; // 一直超限 → 顶在最高档
    }

    // 迟滞：当前档与目标档之间，避免 1~2 档之间来回跳。
    if (_gear > 0) {
      // 只在目标档比当前档高超过 1 档才连升；比当前档低超过 1 档才连降。
      if (target > _gear + 1) {
        _gear += 1;
      } else if (target < _gear - 1) {
        _gear -= 1;
      } else {
        _gear = target;
      }
      // 若当前档转速已跌破降档线，强制降一档（除非已在 1 档）。
      final curRpm = _profile.rpmForSpeed(_gear, speedKmh);
      if (_gear > 1 && curRpm < down) _gear -= 1;
    } else {
      _gear = target;
    }

    var rpm = _profile.rpmForSpeed(_gear, speedKmh);
    // 边界：怠速兜底、红区封顶
    rpm = math.max(_profile.idleRpm.toDouble(), rpm);
    rpm = math.min(rpm, _profile.redlineRpm * 0.98);
    return rpm;
  }

  /// 直接读某车速下的理论转速（不含迟滞，用于测试/展示）。
  double rpmAt(int gear1based, double speedKmh) =>
      _profile.rpmForSpeed(gear1based, speedKmh);
}

/// 纵向 G 值估算：以 GPS 车速差分为主（与手机摆放方向无关、离线可用），
/// 可选融合加速度计前向分量；EMA 平滑，抑制抖动。
/// 纯 Dart、无平台依赖，便于单测。
class GForceEstimator {
  GForceEstimator({this.alpha = 0.35, this.gravity = 9.80665});

  /// EMA 平滑系数（0~1），越大越跟手、越小越稳。
  final double alpha;

  /// 重力加速度 m/s²。
  final double gravity;

  double? _lastSpeedKmh;
  int? _lastTsMs;
  double _smoothMss = 0;

  /// 最近一次平滑后的纵向加速度（m/s²）。
  double get longitudinalMss => _smoothMss;

  /// 最近一次 G 值（带符号：正=加速，负=刹车），保留 2 位小数。
  double get g =>
      double.parse((_smoothMss / gravity).toStringAsFixed(2));

  /// 喂入一帧 GPS 车速（km/h）与时间戳（ms），由 dv/dt 求纵向加速度。
  /// 返回最新 G 值。
  double feedGpsSpeed(double speedKmh, int tsMs) {
    if (_lastTsMs != null && _lastSpeedKmh != null) {
      var dt = (tsMs - _lastTsMs!) / 1000.0;
      if (dt > 0.02 && dt <= 2.5) {
        final dv = (speedKmh - _lastSpeedKmh!) / 3.6; // m/s
        final a = dv / dt; // m/s²
        // 异常尖峰（>1.5g）按 GPS 跳点丢弃，不污染平滑。
        final clamped = a.clamp(-1.5 * gravity, 1.2 * gravity);
        _smoothMss = _smoothMss == 0
            ? clamped
            : _smoothMss * (1 - alpha) + clamped * alpha;
      }
    }
    _lastSpeedKmh = speedKmh;
    _lastTsMs = tsMs;
    return g;
  }

  /// 可选：外部前向加速度（m/s²，来自加速度计重力分离后的水平分量），
  /// 与 GPS 差分结果融合（各占一半）。
  void feedAccelMss(double forwardMss) {
    final c = forwardMss.clamp(-1.5 * gravity, 1.2 * gravity);
    if (_smoothMss == 0) {
      _smoothMss = c;
    } else {
      _smoothMss = _smoothMss * 0.6 + c * 0.4;
    }
  }

  /// 静止/切模式时复位。
  void reset() {
    _lastSpeedKmh = null;
    _lastTsMs = null;
    _smoothMss = 0;
  }
}
