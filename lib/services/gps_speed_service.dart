import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 一帧 GPS 速度数据（离线、无需 OBD）。
class GpsFrame {
  const GpsFrame({
    required this.speedKmh,
    required this.valid,
    this.heading,
    this.altitudeM,
    this.speedAccuracyM,
    this.lat,
    this.lng,
  });

  /// 换算后的车速（km/h）；无效时为 0。
  final double speedKmh;

  /// 速度解是否有效（speed>=0 且精度达标）。无效时 UI 显示 0 / "--"。
  final bool valid;

  /// 航向角°、海拔 m、速度精度 m。
  final double? heading;
  final double? altitudeM;
  final double? speedAccuracyM;

  /// 经纬度（赛道自动计圈用；无效解为 null）。
  final double? lat;
  final double? lng;

  /// 精度劣于该值（m）视为速度不可用。
  static const double accuracyBadThreshold = 30.0;

  /// 从 geolocator 的 Position 构造；无效解 → valid=false 且 speed=0。
  factory GpsFrame.fromPosition(Position p) {
    final accuracyOk =
        !p.speedAccuracy.isNaN && p.speedAccuracy <= accuracyBadThreshold;
    final speedOk = p.speed >= 0 && accuracyOk;
    final kmh = speedOk ? p.speed * 3.6 : 0.0;
    return GpsFrame(
      speedKmh: kmh,
      valid: speedOk,
      heading: p.heading.isNaN ? null : p.heading,
      altitudeM: p.altitude.isNaN ? null : p.altitude,
      speedAccuracyM: p.speedAccuracy.isNaN ? null : p.speedAccuracy,
      lat: speedOk ? p.latitude : null,
      lng: speedOk ? p.longitude : null,
    );
  }
}

/// 权限 / 定位服务引导结果。
enum GpsPermissionStatus { ok, serviceDisabled, denied, deniedForever }

/// GPS 速度数据源抽象（便于单测注入 Fake）。
abstract class GpsDataSource {
  Stream<GpsFrame> get frames;
  Stream<double> get longitudinalAccelMss;
  Future<GpsPermissionStatus> ensurePermission();
  Future<void> start();
  Future<void> stop();
}

/// 纯手机 GPS 速度源（快乐表）：离线可用，无需 OBD。
///
/// - 读取 Position.speed(m/s) × 3.6 = km/h；
/// - 进入时检查定位服务与运行时权限（拒绝/未开 → 友好引导，绝不闪退）；
/// - 静止降频降精度省电，行驶切高精度（2GB 车机低功耗）；
/// - 加速度计（userAccelerometer 已去重力）提供纵向 G 辅助分量。
class GpsSpeedService implements GpsDataSource {
  GpsSpeedService();

  final _ctrl = StreamController<GpsFrame>.broadcast();
  final _accelCtrl = StreamController<double>.broadcast();

  StreamSubscription<Position>? _posSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  Timer? _adaptTimer;

  bool _moving = false;
  bool _streamHigh = true;
  int _stationaryTicks = 0;
  GpsPermissionStatus _lastStatus = GpsPermissionStatus.denied;
  GpsPermissionStatus get lastStatus => _lastStatus;
  bool _running = false;

  @override
  Stream<GpsFrame> get frames => _ctrl.stream;

  @override
  Stream<double> get longitudinalAccelMss => _accelCtrl.stream;

  /// 检查定位服务是否开启、权限是否授予；必要时请求权限。
  /// 绝不抛异常：任何失败都映射为明确状态，由 UI 引导"去设置/重试"。
  @override
  Future<GpsPermissionStatus> ensurePermission() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        _lastStatus = GpsPermissionStatus.serviceDisabled;
        return _lastStatus;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        _lastStatus = GpsPermissionStatus.denied;
      } else if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.unableToDetermine) {
        // deniedForever：系统不再弹框，需引导用户去设置。
        _lastStatus = GpsPermissionStatus.deniedForever;
      } else {
        _lastStatus = GpsPermissionStatus.ok;
      }
    } catch (_) {
      // 通道异常（如测试环境）按服务未开处理，不闪退。
      _lastStatus = GpsPermissionStatus.serviceDisabled;
    }
    return _lastStatus;
  }

  @override
  Future<void> start() async {
    if (_running) return;
    final st = await ensurePermission();
    if (st != GpsPermissionStatus.ok) return;
    _running = true;
    _wirePosition(highAccuracy: true);
    _wireAccelerometer();
    // 每 2s 评估一次：静止持续 → 切低精度省电；行驶 → 切高精度。
    _adaptTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _adaptPower();
    });
  }

  void _wirePosition({required bool highAccuracy}) {
    _posSub?.cancel();
    final settings = LocationSettings(
      accuracy: highAccuracy ? LocationAccuracy.high : LocationAccuracy.low,
      distanceFilter: highAccuracy ? 0 : 5, // 静止时 5m 才更新一次
      timeLimit: highAccuracy ? null : const Duration(seconds: 3),
    );
    try {
      _posSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((p) {
        final frame = GpsFrame.fromPosition(p);
        if (frame.valid && frame.speedKmh > 1.0) {
          _moving = true;
          _stationaryTicks = 0;
        } else {
          _stationaryTicks++;
          if (_stationaryTicks >= 3) _moving = false; // 约 6s 无位移 → 静止
        }
        if (!_ctrl.isClosed) _ctrl.add(frame);
      }, onError: (_) {
        // 定位流异常：发一帧无效帧，UI 显示 0/--，不崩。
        if (!_ctrl.isClosed) {
          _ctrl.add(const GpsFrame(speedKmh: 0, valid: false));
        }
      });
    } catch (_) {
      if (!_ctrl.isClosed) {
        _ctrl.add(const GpsFrame(speedKmh: 0, valid: false));
      }
    }
  }

  /// 省电自适应：静止持续 → 切低精度/大距离滤波；行驶 → 切高精度。
  void _adaptPower() {
    if (!_running) return;
    if (_moving != _streamHigh) {
      _streamHigh = _moving;
      _wirePosition(highAccuracy: _moving);
    }
  }

  void _wireAccelerometer() {
    try {
      _accelSub = userAccelerometerEvents.listen((e) {
        // 手机朝向不定：取水平分量中幅值最大的轴向作为"纵向"近似。
        final ax = e.x.abs() >= e.y.abs() && e.x.abs() >= e.z.abs()
            ? e.x
            : (e.y.abs() >= e.z.abs() ? e.y : e.z);
        if (!_accelCtrl.isClosed) _accelCtrl.add(ax);
      }, onError: (_) {});
    } catch (_) {
      // 无加速度计设备：忽略，G 值退化为纯 GPS 差分。
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _adaptTimer?.cancel();
    await _posSub?.cancel();
    await _accelSub?.cancel();
    _posSub = null;
    _accelSub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
    await _accelCtrl.close();
  }
}
