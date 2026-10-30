import 'dart:math' as math;

/// 性能测试计时器（零百 / 零四 / 刹车）。
/// mode=0 加速：0-100 km/h、0-400m（1/4英里）；mode=1 刹车：100-0 距离/时间。
enum PerfState { idle, running, done }

class PerfSnapshot {
  const PerfSnapshot({
    this.mode = 0,
    this.state = PerfState.idle,
    this.userArmed = false,
    this.t = 0,
    this.dist = 0,
    this.peakSpeed = 0,
    this.t100,
    this.t400,
    this.v400,
    this.brakeT,
    this.brakeD,
    this.best100,
    this.best400,
    this.bestBrake,
  });
  final int mode;
  final PerfState state;

  /// 用户是否已在 real/gps 模式下显式按下"开始"（未按绝不计时）。
  final bool userArmed;
  final double t;
  final double dist;
  final double peakSpeed;
  final double? t100;
  final double? t400;
  final double? v400;
  final double? brakeT;
  final double? brakeD;
  final double? best100;
  final double? best400;
  final double? bestBrake;

  PerfSnapshot copyWith({
    int? mode,
    PerfState? state,
    bool? userArmed,
    double? t,
    double? dist,
    double? peakSpeed,
    double? t100,
    double? t400,
    double? v400,
    double? brakeT,
    double? brakeD,
    double? best100,
    double? best400,
    double? bestBrake,
  }) =>
      PerfSnapshot(
        mode: mode ?? this.mode,
        state: state ?? this.state,
        userArmed: userArmed ?? this.userArmed,
        t: t ?? this.t,
        dist: dist ?? this.dist,
        peakSpeed: peakSpeed ?? this.peakSpeed,
        t100: t100 ?? this.t100,
        t400: t400 ?? this.t400,
        v400: v400 ?? this.v400,
        brakeT: brakeT ?? this.brakeT,
        brakeD: brakeD ?? this.brakeD,
        best100: best100 ?? this.best100,
        best400: best400 ?? this.best400,
        bestBrake: bestBrake ?? this.bestBrake,
      );
}

class PerfTimer {
  int _mode = 0;
  PerfState _state = PerfState.idle;
  double _t = 0, _dist = 0, _peak = 0;
  double? _t100, _t400, _v400, _brakeT, _brakeD;
  double? _best100, _best400, _bestBrake;
  bool _armed = false;
  bool _userArmed = false;

  /// 注入历史最佳成绩（从本地持久化恢复）
  void restoreBest({double? best100, double? best400, double? bestBrake}) {
    _best100 = best100;
    _best400 = best400;
    _bestBrake = bestBrake;
  }

  PerfSnapshot get snapshot => PerfSnapshot(
        mode: _mode,
        state: _state,
        userArmed: _userArmed,
        t: _t,
        dist: _dist,
        peakSpeed: _peak,
        t100: _t100,
        t400: _t400,
        v400: _v400,
        brakeT: _brakeT,
        brakeD: _brakeD,
        best100: _best100,
        best400: _best400,
        bestBrake: _bestBrake,
      );

  /// 本次完成时刷新的最佳成绩（供持久化）
  List<double> get newBests =>
      [_best100 ?? double.nan, _best400 ?? double.nan, _bestBrake ?? double.nan];

  void setMode(int m) {
    if (m != _mode) {
      _mode = m;
      reset();
    }
  }

  void reset() {
    _state = PerfState.idle;
    _t = _dist = _peak = 0;
    _t100 = _t400 = _v400 = _brakeT = _brakeD = null;
    _armed = false;
    _userArmed = false;
  }

  /// 用户在 real/gps 模式下显式按下"开始零百加速"：从此刻起按真实车速积分。
  /// 未调用本方法前，[update] 绝不自动进入 running（修复"自顾自演示"）。
  void beginAccelByUser() {
    _mode = 0;
    reset();
    _userArmed = true;
    _state = PerfState.running;
  }

  /// 用户在 real/gps 模式下显式按下"开始刹车测试"：通常已处于高速，
  /// 一经按下即从当前速度积分，直到停稳或用户手动结束。
  void beginBrakeByUser(double currentSpeedKmh) {
    _mode = 1;
    reset();
    _userArmed = true;
    _state = PerfState.running;
    _peak = currentSpeedKmh;
  }

  /// 用户随时手动结束：若正在进行中，按当前已测得的中间量收尾并落最佳成绩。
  void endByUser() {
    if (_state == PerfState.running) {
      if (_mode == 1 && _t > 0.5) {
        _brakeT ??= _t;
        _brakeD ??= _dist;
        if (_bestBrake == null || _t < _bestBrake!) _bestBrake = _t;
      }
      // 加速模式：t100/t400 一旦测得即在 running 分支内落最佳；这里仅结束计时。
    }
    _state = PerfState.done;
  }

  /// 喂入一帧车速。[userDriven]=true 表示 real/gps 用户驱动模式：
  /// 未显式 begin 前 idle 状态绝不自动触发；只在 running 中积分。
  void update(double speed, double dt, {bool userDriven = false}) {
    final dtc = dt.clamp(0.0, 1.0);
    if (userDriven && _state == PerfState.idle) return; // 未点开始，绝不计时
    switch (_state) {
      case PerfState.idle:
        if (_mode == 0) {
          if (speed >= 2) {
            _state = PerfState.running;
            _t = _dist = _peak = 0;
          }
        } else {
          if (speed >= 100) _armed = true;
          if (_armed && speed < 95) {
            _state = PerfState.running;
            _t = _dist = 0;
            _peak = speed;
          }
        }
        break;
      case PerfState.running:
        _t += dtc;
        _dist += speed / 3.6 * dtc;
        _peak = math.max(_peak, speed);
        if (_mode == 0) {
          if (_t100 == null && speed >= 100) {
            _t100 = _t;
            if (_best100 == null || _t < _best100!) _best100 = _t;
          }
          if (_t400 == null && _dist >= 402.3) {
            _t400 = _t;
            _v400 = speed;
            if (_best400 == null || _t < _best400!) _best400 = _t;
          }
          if (_t100 != null && _t400 != null) _state = PerfState.done;
          if (_t > 30) _state = PerfState.done;
        } else {
          if (speed <= 1.5) {
            _brakeT = _t;
            _brakeD = _dist;
            if (_bestBrake == null || _t < _bestBrake!) _bestBrake = _t;
            _state = PerfState.done;
          }
          if (_t > 20) _state = PerfState.done;
        }
        break;
      case PerfState.done:
        if (speed < 2) {
          _state = PerfState.idle;
          if (_mode == 1) _armed = false;
        }
        break;
    }
  }
}
