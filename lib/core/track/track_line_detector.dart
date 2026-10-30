import 'dart:math' as math;

/// 赛道起点线（S/F）自动识别：基于 GPS 坐标匹配的纯逻辑状态机。
///
/// 思路（轻量、无需内置赛道库）：
///  1. 用户在起点线处点"学习起点"，记录 S/F 经纬度；
///  2. 车辆驶离外圈（[armRadiusM]）后进入"武装"状态；
///  3. 武装后车辆再次进入内圈（[crossRadiusM]）且在动 → 判定为冲线，完成一圈；
///  4. 每圈用时 = 本次冲线时刻 - 上次冲线时刻（第一圈从离开外圈起算近似）。
///
/// 全程纯函数式，可注入假坐标单测。
class TrackLineDetector {
  TrackLineDetector({
    this.crossRadiusM = 25,
    this.armRadiusM = 120,
    this.minSpeedKmh = 5,
  });

  /// 触发冲线的半径（米）。GPS 精度差时调大。
  final double crossRadiusM;

  /// 驶离多远才算"离开起点"从而武装（米）。
  final double armRadiusM;

  /// 低于此车速不判定冲线（避免原地/慢挪误触）。
  final double minSpeedKmh;

  double? _originLat;
  double? _originLng;

  /// 是否已学习起点线。
  bool get hasOrigin => _originLat != null && _originLng != null;

  double? _armedSinceMs;
  double? _lastCrossMs;
  int _lapCount = 0;

  int get lapCount => _lapCount;
  double? get lastCrossMs => _lastCrossMs;

  /// 在当前位置学习为起点线。
  void learnOrigin(double lat, double lng) {
    _originLat = lat;
    _originLng = lng;
    _armedSinceMs = null;
    _lastCrossMs = null;
    _lapCount = 0;
  }

  void clear() {
    _originLat = null;
    _originLng = null;
    _armedSinceMs = null;
    _lastCrossMs = null;
    _lapCount = 0;
  }

  /// 喂一帧位置。返回本帧是否完成一圈（冲线）以及该圈用时秒。
  /// 未学习起点 / 数据无效时返回 null。
  TrackCrossResult? feed(
      double lat, double lng, double speedKmh, double nowMs) {
    if (!hasOrigin) return null;
    final d = haversineM(_originLat!, _originLng!, lat, lng);

    // 尚未离开外圈：保持未武装。
    if (d > armRadiusM) {
      _armedSinceMs ??= nowMs;
      return null;
    }

    // 已在内圈。
    if (d <= crossRadiusM) {
      final armed = _armedSinceMs != null;
      final moving = speedKmh >= minSpeedKmh;
      if (armed && moving) {
        final prev = _lastCrossMs ?? _armedSinceMs;
        final lapSec = (nowMs - prev!) / 1000.0;
        _lastCrossMs = nowMs;
        _lapCount++;
        // 冲线后立即解除武装，等待再次驶离外圈。
        _armedSinceMs = null;
        return TrackCrossResult(
          lap: _lapCount,
          lapSeconds: lapSec,
        );
      }
    }
    return null;
  }

  /// 两经纬度间球面距离（米）。
  static double haversineM(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}

/// 一次冲线结果。
class TrackCrossResult {
  const TrackCrossResult({required this.lap, required this.lapSeconds});
  final int lap;
  final double lapSeconds;
}
