// GPS 快乐表（v2.9.0）单元测试：
//  - m/s→km/h 换算、speed=-1 / 精度差降级；
//  - 马6 齿比反推档位与虚拟转速（静止空档、随速升档、不超红区、迟滞不跳档）；
//  - 纵向 G 值（正加速 / 负刹车，合理范围，GPS 差分不把重力当加减速）；
//  - Fake GPS 流驱动 TelemetryService：速度正确、OBD 专有字段为 null（不造假）、
//    虚拟转速/档位被填充、性能计时仅在用户点开始后进行；
//  - 3s 上报门控：gps 定位有效才 shouldReportToCloud。
import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obd_dashboard/core/perf/perf_timer.dart';
import 'package:obd_dashboard/core/vehicle/gps_virtual_drivetrain.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/services/gps_speed_service.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';

/// 测试用 Fake GPS 源：直接吐 GpsFrame，无平台通道依赖。
class FakeGpsSource implements GpsDataSource {
  final _ctrl = StreamController<GpsFrame>.broadcast();
  final _accelCtrl = StreamController<double>.broadcast();

  @override
  Stream<GpsFrame> get frames => _ctrl.stream;
  @override
  Stream<double> get longitudinalAccelMss => _accelCtrl.stream;
  @override
  Future<GpsPermissionStatus> ensurePermission() async =>
      GpsPermissionStatus.ok;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}

  void emit(GpsFrame f) => _ctrl.add(f);
}

Position mkPos({double speed = 0, double accuracy = 1}) => Position(
      latitude: 31.2,
      longitude: 121.5,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 10,
      altitudeAccuracy: 5,
      heading: 90,
      headingAccuracy: 5,
      speed: speed,
      speedAccuracy: accuracy,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('GpsFrame 换算与降级', () {
    test('正常速度 m/s → km/h', () {
      final f = GpsFrame.fromPosition(mkPos(speed: 10, accuracy: 2));
      expect(f.valid, isTrue);
      expect(f.speedKmh, closeTo(36.0, 0.01));
    });
    test('speed=-1（无速度解）→ 无效，速度 0', () {
      final f = GpsFrame.fromPosition(mkPos(speed: -1, accuracy: 2));
      expect(f.valid, isFalse);
      expect(f.speedKmh, 0);
    });
    test('精度 >30m → 无效', () {
      final f = GpsFrame.fromPosition(mkPos(speed: 20, accuracy: 45));
      expect(f.valid, isFalse);
      expect(f.speedKmh, 0);
    });
  });

  group('马6 齿比反推档位/虚拟转速', () {
    final p = VehicleProfile.byId('mazda6_2011');

    test('静止回空档、怠速转速', () {
      final d = GpsVirtualDrivetrain(p);
      final rpm = d.update(0);
      expect(d.gear, 0);
      expect(rpm, closeTo(800, 1));
    });

    test('随车速逐级升档，转速落在合理带、不超红区', () {
      final d = GpsVirtualDrivetrain(p);
      final gears = <int>[];
      for (final v in [0.0, 15.0, 30.0, 60.0, 90.0, 120.0]) {
        final rpm = d.update(v);
        gears.add(d.gear);
        // 转速夹在怠速~0.98 红区之间
        expect(rpm, greaterThanOrEqualTo(p.idleRpm - 1));
        expect(rpm, lessThanOrEqualTo(p.redlineRpm * 0.98 + 1));
      }
      // 空档 → 1 → 2 → 3 → 4 → 5，逐级上升不跳档
      expect(gears, [0, 1, 2, 3, 4, 5], reason: '实际档位序列 $gears');
    });

    test('迟滞：临界车速不反复跳档', () {
      final d = GpsVirtualDrivetrain(p);
      d.update(60);
      final g1 = d.gear;
      // 速度微调，档位不应立刻来回跳
      d.update(61);
      d.update(59);
      expect((d.gear - g1).abs() <= 1, isTrue);
    });
  });

  group('纵向 G 值估算', () {
    test('匀加速 → 正 G', () {
      final g = GForceEstimator();
      g.feedGpsSpeed(0, 0);
      final v = g.feedGpsSpeed(36, 2000); // 0→36km/h 用 2s：a=5 m/s² ≈ 0.51g
      expect(v, inInclusiveRange(0.3, 0.8));
      expect(v, greaterThan(0));
    });
    test('全力刹车 → 负 G', () {
      final g = GForceEstimator();
      g.feedGpsSpeed(36, 0);
      final b = g.feedGpsSpeed(0, 2000); // 36→0 用 2s：a=-5 m/s² ≈ -0.51g
      expect(b, inInclusiveRange(-0.8, -0.3));
      expect(b, lessThan(0));
    });
    test('速度恒定 → G 趋近 0（不把匀速误判为加减速）', () {
      final g = GForceEstimator();
      g.feedGpsSpeed(60, 0);
      g.feedGpsSpeed(60, 1000);
      g.feedGpsSpeed(60, 2000);
      expect(g.g.abs(), lessThan(0.05));
    });
  });

  group('TelemetryService GPS 帧集成', () {
    test('GPS 帧：速度正确、OBD 专有字段为 null、虚拟转速/档位被填充', () async {
      final tele = TelemetryService();
      final fake = FakeGpsSource();
      tele.gpsSource = fake;
      await tele.selectMode('gps');
      addTearDown(tele.dispose);

      fake.emit(const GpsFrame(
          speedKmh: 60, valid: true, heading: 90, altitudeM: 10,
          speedAccuracyM: 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final d = tele.current;
      expect(d.source, 'gps');
      expect(d.speed, closeTo(60, 0.01));
      // OBD 专有 PID 一律 null，绝不造假
      expect(d.coolant, isNull);
      expect(d.voltage, isNull);
      expect(d.oilTemp, isNull);
      expect(d.intakeTemp, isNull);
      expect(d.map, isNull);
      expect(d.maf, isNull);
      expect(d.load, isNull);
      expect(d.throttle, isNull);
      expect(d.fuelLevel, isNull);
      // 虚拟档位/转速被填充
      expect(d.gear, greaterThanOrEqualTo(1));
      expect(d.rpm, greaterThan(0));
      expect(d.rpm, lessThan(6500));
      expect(d.altitude, closeTo(10, 0.01));
      expect(d.heading, closeTo(90, 0.01));
    });

    test('无效 GPS 帧 → 速度 0，不报错；恢复后自动有效', () async {
      final tele = TelemetryService();
      final fake = FakeGpsSource();
      tele.gpsSource = fake;
      await tele.selectMode('gps');
      addTearDown(tele.dispose);

      fake.emit(const GpsFrame(speedKmh: 0, valid: false));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.current.speed, 0);
      expect(tele.current.gear, 0);

      fake.emit(const GpsFrame(speedKmh: 80, valid: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.current.speed, closeTo(80, 0.01));
      expect(tele.current.gear, greaterThanOrEqualTo(1));
    });

    test('性能计时仅在用户点开始后进行（不自顾自跑）', () async {
      final tele = TelemetryService();
      final fake = FakeGpsSource();
      tele.gpsSource = fake;
      await tele.selectMode('gps');
      addTearDown(tele.dispose);

      // 高速帧进来，但用户还没点开始 → 计时器保持 idle
      fake.emit(const GpsFrame(speedKmh: 60, valid: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.perf.state, PerfState.idle,
          reason: '未点开始绝不能自动计时');

      // 用户点开始零百
      tele.beginPerfByUser(0);
      expect(tele.perf.userArmed, isTrue);

      // 喂入加速序列 0→100
      for (final v in [0.0, 20.0, 40.0, 60.0, 80.0, 100.0]) {
        fake.emit(GpsFrame(speedKmh: v, valid: true));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(tele.perf.t100, isNotNull, reason: '到达 100km/h 应记录零百时间');
      expect(tele.perf.state, anyOf(PerfState.running, PerfState.done));
    });

    test('3s 上报门控：gps 定位有效才上报', () async {
      final tele = TelemetryService();
      final fake = FakeGpsSource();
      tele.gpsSource = fake;
      await tele.selectMode('gps');
      addTearDown(tele.dispose);

      // 无效帧 → 不上报
      fake.emit(const GpsFrame(speedKmh: 0, valid: false));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.shouldReportToCloud, isFalse);

      // 有效帧 → 可上报（登录由定时器外层门控）
      fake.emit(const GpsFrame(speedKmh: 70, valid: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.shouldReportToCloud, isTrue);
      expect(tele.current.source, 'gps');
    });
  });
}
