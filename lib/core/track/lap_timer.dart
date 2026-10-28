import 'dart:async';
import 'package:flutter/foundation.dart';

/// 圈速计时器（赛道日 / 圈速挑战）。
///
/// 手动开始/结束每一圈，记录最佳圈速；
/// 圈进行中实时对比当前圈与最佳圈的进度，给出
/// 预测差值（快→绿，慢→红），数据可持久化。
class LapTimer extends ChangeNotifier {
  Timer? _ticker;
  bool _running = false;

  // 当前圈
  double _currentLap = 0; // 已用秒
  int _lapCount = 0;

  // 历史
  final List<double> _lapHistory = [];
  double? _bestLap;
  double? _lastLap;

  // 预测差值（当前圈 - 最佳圈，负数=更快）
  double? _predictedDelta;

  // 恢复最佳
  void restore({double? best, int? lapCount}) {
    _bestLap = best;
    _lapCount = lapCount ?? 0;
  }

  bool get isRunning => _running;
  double get currentLap => _currentLap;
  int get lapCount => _lapCount;
  double? get bestLap => _bestLap;
  double? get lastLap => _lastLap;
  List<double> get lapHistory => _lapHistory;
  double? get predictedDelta => _predictedDelta;

  /// 开始计时（100ms 精度）。
  void start() {
    if (_running) return;
    _running = true;
    _currentLap = 0;
    _predictedDelta = null;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _currentLap += 0.1;
      _updatePrediction();
      notifyListeners();
    });
    notifyListeners();
  }

  /// 结束当前圈。
  double? endLap() {
    if (!_running) return null;
    _ticker?.cancel();
    _running = false;
    _lastLap = _currentLap;
    _lapHistory.add(_currentLap);
    _lapCount++;
    if (_bestLap == null || _currentLap < _bestLap!) {
      _bestLap = _currentLap;
    }
    _predictedDelta = null;
    notifyListeners();
    return _currentLap;
  }

  /// 重置全部。
  void reset() {
    _ticker?.cancel();
    _running = false;
    _currentLap = 0;
    _lapCount = 0;
    _lastLap = null;
    _bestLap = null;
    _lapHistory.clear();
    _predictedDelta = null;
    notifyListeners();
  }

  /// 简单预测：基于当前时间与最佳圈的线性对比。
  /// 实际赛道系统按 GPS 位置匹配；此处用车速加权做近似。
  void _updatePrediction() {
    if (_bestLap == null || _currentLap < 1) {
      _predictedDelta = null;
      return;
    }
    // 线性进度对比（演示用）
    final progress = (_currentLap / _bestLap!).clamp(0.0, 1.0);
    // 若当前圈已用时间超过最佳圈的进度比例，说明偏慢
    if (progress > 0.95) {
      _predictedDelta = _currentLap - _bestLap!;
    }
  }

  /// 预测状态：-1 更快（绿），0 接近，1 更慢（红），null 无数据。
  int? get predictionState {
    final d = _predictedDelta;
    if (d == null) return null;
    if (d < -0.1) return -1;
    if (d > 0.1) return 1;
    return 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// 格式化时间：mm:ss.d
String formatLapTime(double seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(1).padLeft(4, '0')}';
}
