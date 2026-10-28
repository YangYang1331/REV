// 行程 coast 状态机（纯逻辑）单测 + TelemetryService 增量集成：
//  - coast 四分支：红灯/滑行停车不切段、真熄火 rpm 长时间归零落盘、
//    熄火后移动/转速恢复开新段、行驶静默；
//  - GPS 静止死区（低速按 0、回空档、怠速）；
//  - OBD 连上后 GPS 自动让位；
//  - ObdData.showUnsupportedAsDashes / isGpsEstimated 显示规则。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obd_dashboard/core/vehicle/coast_state_machine.dart';
import 'package:obd_dashboard/models/obd_data.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('CoastStateMachine 四分支', () {
    // 马6：怠速 800，offRpm=320，idleLow=480，idleHigh=1280，offConfirm=5s。
    CoastStateMachine m() => CoastStateMachine(idleRpm: 800);

    test('分支1 红灯/滑行停车：速度0但转速怠速 → 不切段、不落盘', () {
      final c = m();
      // 先开起来
      expect(c.update(60, 2500, 0), CoastEvent.none);
      // 到红灯：停住但发动机怠速
      expect(c.update(0, 800, 1000), CoastEvent.none);
      expect(c.update(0, 820, 3000), CoastEvent.none);
      expect(c.update(0, 790, 6000), CoastEvent.none);
      // 等待期间绝不落盘
      expect(c.state, isNot(CoastState.off));
      // 又起步：行程继续，不开新段
      expect(c.update(40, 1800, 8000), CoastEvent.none);
      expect(c.state, CoastState.driving);
    });

    test('分支2 真熄火：转速长时间归零 → endTrip 落盘', () {
      final c = m();
      c.update(0, 800, 0); // 怠速停车
      // 拧钥匙熄火：转速掉到 0
      c.update(0, 0, 1000);
      c.update(0, 0, 3000);
      // 不足 5s 不确认
      expect(c.update(0, 0, 4000), CoastEvent.none);
      expect(c.state, isNot(CoastState.off));
      // 满 5s → 落盘结束
      expect(c.update(0, 0, 6000), CoastEvent.endTrip);
      expect(c.state, CoastState.off);
    });

    test('分支3 熄火后又移动/转速恢复 → beginNewTrip 开新段', () {
      final c = m();
      c.update(0, 800, 0);
      c.update(0, 0, 1000);
      expect(c.update(0, 0, 6000), CoastEvent.endTrip);
      expect(c.state, CoastState.off);
      // 熄火期间静止：不动
      expect(c.update(0, 0, 7000), CoastEvent.none);
      // 打火、又开起来
      expect(c.update(0, 900, 8000), CoastEvent.beginNewTrip);
      expect(c.state, CoastState.driving);
    });

    test('分支4 行驶中静默：只跑不打扰', () {
      final c = m();
      expect(c.update(50, 2000, 0), CoastEvent.none);
      expect(c.update(90, 3200, 1000), CoastEvent.none);
      expect(c.update(120, 3800, 2000), CoastEvent.none);
      expect(c.state, CoastState.driving);
    });

    test('行驶中转速短暂掉线（<确认时长）不误判熄火', () {
      final c = m();
      c.update(60, 2600, 0);
      // 偶发一帧转速=0，但马上恢复
      c.update(60, 0, 1000);
      expect(c.update(60, 2600, 2000), CoastEvent.none);
      expect(c.state, CoastState.driving);
    });
  });

  group('ObdData 显示规则', () {
    test('demo/gps 把无数据 PID 显示为 --；real 按支持度隐藏', () {
      expect(const ObdData(source: 'demo').showUnsupportedAsDashes, isTrue);
      expect(const ObdData(source: 'gps').showUnsupportedAsDashes, isTrue);
      expect(const ObdData(source: 'obd').showUnsupportedAsDashes, isFalse);
      expect(const ObdData(source: 'gps').isGpsEstimated, isTrue);
      expect(const ObdData(source: 'obd').isGpsEstimated, isFalse);
    });
  });

  group('TelemetryService GPS 增量', () {
    test('静止死区：低速 GPS 帧按 0 处理、回空档、怠速', () async {
      final tele = TelemetryService();
      final fake = FakeGpsSource();
      tele.gpsSource = fake;
      await tele.selectMode('gps');
      addTearDown(tele.dispose);

      // 1.5km/h 的 GPS 漂移 → 死区归 0
      fake.emit(const GpsFrame(speedKmh: 1.5, valid: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.current.speed, 0);
      expect(tele.current.gear, 0);
      expect(tele.current.rpm, closeTo(800, 2));
    });

    test('OBD 连上后 GPS 让位：自动切 real 并停掉 GPS 源', () async {
      final tele = TelemetryService();
      final fake = FakeGpsSource();
      tele.gpsSource = fake;
      await tele.selectMode('gps');
      addTearDown(tele.dispose);

      fake.emit(const GpsFrame(speedKmh: 60, valid: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.isGpsMode, isTrue);
      expect(tele.current.source, 'gps');

      // USB/BLE OBD 连上，推入真实帧
      tele.onRealFrame(const ObdData(
          connected: true, source: 'obd', speed: 55, rpm: 1400, gear: 3));
      expect(tele.isRealMode, isTrue, reason: 'OBD 连上应自动切真实模式');
      expect(tele.current.source, 'obd');

      // GPS 源已停：再吐 GPS 帧不应再改写当前数据
      fake.emit(const GpsFrame(speedKmh: 99, valid: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tele.current.source, 'obd');
    });
  });
}
