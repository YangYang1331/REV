import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:obd_dashboard/core/vehicle/fuel_calc.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 演示数据引擎。
///
/// 两种运行方式：
///  - 正常循环：地板油 → 换挡 → 冲高速 → 减速 → 停稳，随机重复。
///  - 性能测试场景：由 [runPerfScenario] 触发，按用户选择的
///    零百/零四（mode=0）或 100-0 刹车（mode=1）严格执行，
///    走完一次后自动恢复正常循环。
class DemoEngine extends ChangeNotifier {
  DemoEngine(this.profile);

  VehicleProfile profile;
  Timer? _timer;
  final Random _r = Random();

  /// 受控性能测试场景走完（车已停稳）时回调一次，供 Telemetry 解除武装并保存成绩。
  VoidCallback? onPerfComplete;

  double _speed = 0, _rpm = 800, _coolant = 88;
  int _gear = 1;
  bool _accelerating = true;
  int _cycle = 0, _phase = 0, _tick = 0;
  late int _shiftPoint;
  late double _peakSpeed, _brake, _redPull;
  late bool _overheat, _forceDownDone;

  // ── 性能测试场景 ──
  // 0=正常循环，1=零百/零四加速测试，2=100-0 刹车测试
  int _perfScenario = 0;
  int _perfPhase = 0;
  double _perfDist = 0;
  // 启动压降模拟帧数（加速测试起步时）
  int _crankFrames = 0;

  ObdData _current = ObdData.empty;
  ObdData get current => _current;
  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _speed = 0;
    _gear = 1;
    _rpm = profile.idleRpm.toDouble();
    _coolant = 88;
    _cycle = 0;
    _phase = 0;
    _perfScenario = 0;
    _recompute();
    _timer = Timer.periodic(const Duration(milliseconds: 90), (_) => _tick2());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 触发性能测试场景。mode=0 零百/零四，mode=1 刹车。
  void runPerfScenario(int mode) {
    _perfScenario = mode == 0 ? 1 : 2;
    _perfPhase = 0;
    _perfDist = 0;
    if (_perfScenario == 1) {
      // 加速测试：立即回到静止，准备全力起步
      _speed = 0;
      _gear = 1;
      _rpm = profile.idleRpm.toDouble();
      _accelerating = true;
      _crankFrames = 5; // 模拟启动压降
    } else {
      // 刹车测试：先加速到 100+（若当前速度不够）
      _accelerating = true;
    }
    notifyListeners();
  }

  void _recompute() {
    _shiftPoint = _randomShiftPoint();
    _peakSpeed = 140 + _r.nextDouble() * 55;
    _brake = 1.3 + _r.nextDouble() * 3.0;
    _redPull = _r.nextDouble() < 0.5 ? 1 : 0;
    _overheat = _cycle % 3 == 1;
    _forceDownDone = false;
  }

  int _randomShiftPoint() {
    final red = profile.redlineRpm;
    if (_r.nextDouble() < 0.5) {
      return (2600 + _r.nextDouble() * 1700).round();
    }
    return (red - 100 + _r.nextDouble() * 120).round();
  }

  void _tick2() {
    _tick++;
    if (_perfScenario > 0) {
      _tickPerf();
      return;
    }
    _phase++;

    final coolantTarget = _overheat && _accelerating && _phase > 25
        ? 118 + _r.nextDouble() * 2
        : _overheat
            ? 96.0
            : _accelerating
                ? 92 + (_speed / 220) * 6
                : 88 + (_speed / 220) * 3;
    _coolant = (_coolant + (coolantTarget - _coolant) * 0.02)
        .clamp(85.0, 122.0);

    if (_accelerating) {
      final accel = (2.6 / _gear) * (0.85 + _r.nextDouble() * 0.3);
      _speed = min(
          _speed + accel, _gear >= profile.maxGear ? _peakSpeed : 240.0);
      var target = profile.rpmForSpeed(_gear, _speed);
      if (_redPull > 0) target = max(target, profile.rpmForSpeed(_gear, _speed));
      _rpm = (_rpm + (target - _rpm) * 0.35 + (_r.nextDouble() - 0.5) * 40)
          .clamp(profile.idleRpm.toDouble(), double.infinity);
      if (_rpm >= _shiftPoint) {
        if (_gear < profile.maxGear) {
          _gear++;
          _rpm = profile.rpmForSpeed(_gear, _speed) *
              (1.0 + _r.nextDouble() * 0.04);
        } else if (_speed >= _peakSpeed) {
          _accelerating = false;
          _phase = 0;
        }
      }
    } else {
      _speed = max(
          0.0, _speed - _brake * (0.7 + _r.nextDouble() * 0.6));
      if (!_forceDownDone && _speed > 90 && _gear >= 4 &&
          _r.nextDouble() < 0.03) {
        _gear = max(1, _gear - 3);
        _forceDownDone = true;
      }
      final target = _speed < 2
          ? profile.idleRpm.toDouble()
          : profile.rpmForSpeed(_gear, _speed);
      _rpm = _rpm + (target - _rpm) * 0.30 + (_r.nextDouble() - 0.5) * 30;
      if (_speed < 2) {
        _gear = 1;
        _rpm = profile.idleRpm.toDouble();
        _cycle++;
        _phase = 0;
        _recompute();
        _accelerating = true;
      } else if (_rpm < profile.shiftDownRpm && _gear > 1) {
        final skip = _r.nextDouble() < 0.22 && _gear >= 3 ? 2 : 1;
        _gear = max(1, _gear - skip);
        _rpm = profile.rpmForSpeed(_gear, _speed);
      }
    }

    _emitFrame(throttle: _accelerating ? 82 + _r.nextDouble() * 18 : 4 + _r.nextDouble() * 6);
  }

  /// 性能测试场景的状态机。
  void _tickPerf() {
    const dt = 0.09;

    if (_perfScenario == 1) {
      // ── 零百 / 零四加速测试 ──
      if (_crankFrames > 0) {
        // 启动压降：起动机带动，电压短暂跌落，转速缓慢爬升
        _crankFrames--;
        _rpm = profile.idleRpm.toDouble() + (5 - _crankFrames) * 120;
        _speed = 0;
        final crankV = 10.6 + _crankFrames * 0.15;
        _emitFrame(throttle: 100.0, voltage: crankV);
        return;
      }
      if (_perfPhase == 0) {
        // 全力加速：按档位递减的加速度（贴近马6 2.0L 5AT，0-100≈11s）
        const accelByGear = [1.0, 0.75, 0.55, 0.40, 0.30];
        final gi = (_gear - 1).clamp(0, accelByGear.length - 1);
        final accel = accelByGear[gi] * (0.92 + _r.nextDouble() * 0.16);
        _speed = min(_speed + accel, 180.0);
        _perfDist += _speed / 3.6 * dt;

        final target = profile.rpmForSpeed(_gear, _speed);
        _rpm = (_rpm + (target - _rpm) * 0.4 + (_r.nextDouble() - 0.5) * 30)
            .clamp(profile.idleRpm.toDouble(), double.infinity);

        // 换挡点设在红区下方一点（全力加速）
        final perfShift = (profile.redlineRpm * 0.97).round();
        if (_rpm >= perfShift && _gear < profile.maxGear) {
          _gear++;
          _rpm = profile.rpmForSpeed(_gear, _speed) * 1.02;
        }

        // 水温随加速略升
        _coolant = (_coolant + (94 - _coolant) * 0.01).clamp(85.0, 100.0);

        // 零四完成（距离到 400m，且速度已过 100）后进入减速
        if (_perfDist >= 420 && _speed >= 100) {
          _perfPhase = 1;
        }
      } else {
        // 测试后减速停稳
        _speed = max(0.0, _speed - 3.2 * (0.9 + _r.nextDouble() * 0.2));
        _perfDist += _speed / 3.6 * dt;
        final target = _speed < 2
            ? profile.idleRpm.toDouble()
            : profile.rpmForSpeed(_gear, _speed);
        _rpm = _rpm + (target - _rpm) * 0.25;
        if (_rpm < profile.shiftDownRpm && _gear > 1) {
          _gear = max(1, _gear - 1);
          _rpm = profile.rpmForSpeed(_gear, _speed);
        }
        if (_speed < 2) {
          _finishPerf();
          return;
        }
      }
      _emitFrame(throttle: _perfPhase == 0 ? 100.0 : 0.0);
    } else {
      // ── 100-0 刹车测试 ──
      if (_perfPhase == 0) {
        // 先全力加速到 100+（按档位递减，贴近真实提速）
        const accelByGear = [1.0, 0.75, 0.55, 0.40, 0.30];
        final gi = (_gear - 1).clamp(0, accelByGear.length - 1);
        final accel = accelByGear[gi] * (0.9 + _r.nextDouble() * 0.15);
        _speed = min(_speed + accel, 130.0);
        final target = profile.rpmForSpeed(_gear, _speed);
        _rpm = (_rpm + (target - _rpm) * 0.4);
        if (_rpm >= (profile.redlineRpm * 0.95) && _gear < profile.maxGear) {
          _gear++;
          _rpm = profile.rpmForSpeed(_gear, _speed) * 1.02;
        }
        _coolant = (_coolant + (93 - _coolant) * 0.01).clamp(85.0, 100.0);
        // 到 108 左右开始刹车（越过 100 武装，刹车后跌破 95 触发计时）
        if (_speed >= 108) {
          _perfPhase = 1;
        }
        _emitFrame(throttle: 100.0);
      } else {
        // 全力刹车（约 0.9g，100-0 用时≈3s、距离≈40m）
        _speed = max(0.0, _speed - 2.9 * (0.92 + _r.nextDouble() * 0.16));
        _perfDist += _speed / 3.6 * dt;
        final target = _speed < 2
            ? profile.idleRpm.toDouble()
            : profile.rpmForSpeed(_gear, _speed);
        _rpm = _rpm + (target - _rpm) * 0.2;
        if (_rpm < profile.shiftDownRpm && _gear > 1) {
          _gear = max(1, _gear - 1);
          _rpm = profile.rpmForSpeed(_gear, _speed);
        }
        if (_speed < 2) {
          _finishPerf();
          return;
        }
        _emitFrame(throttle: 0.0);
      }
    }
  }

  /// 性能测试结束：恢复正常循环。
  void _finishPerf() {
    _perfScenario = 0;
    _perfPhase = 0;
    _perfDist = 0;
    _speed = 0;
    _gear = 1;
    _rpm = profile.idleRpm.toDouble();
    _accelerating = false;
    _phase = 0;
    // 先补发一帧 0 速度，确保 PerfTimer 收到"停稳"（刹车判定完成）。
    _emitFrame(throttle: 0.0);
    // 通知上层：解除武装、持久化最佳成绩。
    onPerfComplete?.call();
    _accelerating = true;
    _recompute();
    _tick2();
  }

  /// 中止受控场景（切换项目/手动重置）：不发完成回调，直接回到普通循环。
  void cancelPerfScenario() {
    if (_perfScenario == 0) return;
    _perfScenario = 0;
    _perfPhase = 0;
    _perfDist = 0;
    _phase = 0;
    _accelerating = true;
    _recompute();
  }

  /// 根据当前状态生成一帧数据。
  void _emitFrame({required double throttle, double? voltage}) {
    final load = _accelerating
        ? (42 + _speed * 0.22).clamp(0.0, 96.0)
        : (12 + _speed * 0.08).clamp(0.0, 40.0);
    final map = 38 + load * 0.62 + (_accelerating ? 14 : 0);
    final oilTemp = (_coolant - 3 + sin(_tick / 130.0) * 1.5).clamp(80.0, 120.0);
    final intakeTemp =
        (28 + load * 0.16 + (_coolant - 88) * 0.30 + sin(_tick / 70.0) * 1.5)
            .clamp(28.0, 62.0);
    final maf = FuelCalc.mafFromMap(
        map, _rpm, intakeTemp, profile.displacementL);
    final atfTemp = (_coolant - 10 + sin(_tick / 160.0) * 1.5).clamp(70.0, 110.0);
    final catTemp = (380 + load * 2.8 + sin(_tick / 50.0) * 12).clamp(300.0, 720.0);
    final fuelRailP = (0.30 + load * 0.0009).clamp(0.25, 0.42);
    final ignAdv = _accelerating
        ? 8 + (100 - load) * 0.18
        : 18 + (100 - load) * 0.12;
    final torque = (load * 0.9 + (_accelerating ? 8 : 0)).clamp(0.0, 99.0);
    final ltft = sin(_tick / 200.0) * 3.5;
    final absLoad = (load * 1.4).clamp(0.0, 95.0);
    final altitude = 6 + sin(_tick / 300.0) * 2;

    _current = ObdData(
      connected: true,
      source: 'demo',
      rpm: _rpm.clamp(profile.idleRpm * 0.9, profile.redlineRpm + 250).round(),
      speed: _speed,
      coolant: _coolant,
      oilTemp: oilTemp,
      intakeTemp: intakeTemp,
      ambient: 24,
      voltage: voltage ??
          (13.7 + (_accelerating ? 0.6 : 0.1) + _r.nextDouble() * 0.2),
      map: map,
      maf: maf,
      atfTemp: atfTemp,
      catTemp: catTemp,
      fuelRailP: fuelRailP,
      ignAdv: ignAdv,
      torque: torque,
      ltft: ltft,
      absLoad: absLoad,
      altitude: altitude,
      load: load,
      throttle: throttle,
      fuelLevel: 62,
      gear: _speed < 2 ? 0 : _gear,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
