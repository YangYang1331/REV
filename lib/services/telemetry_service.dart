import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:obd_dashboard/core/perf/perf_timer.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/game/game_telemetry.dart';
import 'package:obd_dashboard/core/vehicle/coast_state_machine.dart';
import 'package:obd_dashboard/core/vehicle/fuel_calc.dart';
import 'package:obd_dashboard/core/vehicle/gps_virtual_drivetrain.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/models/obd_data.dart';
import 'package:obd_dashboard/services/demo_engine.dart';
import 'package:obd_dashboard/services/engine_sound_service.dart';
import 'package:obd_dashboard/services/gps_speed_service.dart';

/// 统一遥测服务：无论演示 / 真实 / 游戏，UI 只订阅这一份。
/// 负责：
///  - 档位反推（真实 OBD 按车型速比；演示源直接给）
///  - 速度校准系数
///  - 速度密度法补 MAF、MAP 反算海拔
///  - 行程积分（里程/油耗/用时，限制单帧 dt，防切后台灌入）
///  - 数据丢失保护（2s 无有效帧 → 归零 rpm/fuel/负荷；6s → 视为熄火）
///  - 性能测试计时（零百/零四/刹车）
class TelemetryService extends ChangeNotifier {
  TelemetryService() {
    _demo = DemoEngine(VehicleProfile.byId('mazda6_2011'));
    _profile = VehicleProfile.byId('mazda6_2011');
    _gpsDrivetrain = GpsVirtualDrivetrain(_profile);
    _perf.restoreBest(
      best100: AppStore.instance.best100,
      best400: AppStore.instance.best400,
      bestBrake: AppStore.instance.bestBrake,
    );
  }

  late DemoEngine _demo;
  VehicleProfile _profile = VehicleProfile.byId('mazda6_2011');
  VehicleProfile get profile => _profile;

  /// 行程 coast 状态机（纯逻辑、可注入时钟，便于单测四分支）。
  late CoastStateMachine _coast =
      CoastStateMachine(idleRpm: _profile.idleRpm.toDouble());
  CoastState get coastState => _coast.state;

  final PerfTimer _perf = PerfTimer();
  PerfSnapshot get perf => _perf.snapshot;

  // 演示模式下，仅在用户点"开始"进入受控性能测试场景时才让速度喂计时器；
  // 否则普通 demo 循环会自动触发计时（自顾自地跑）。
  bool _perfDemoActive = false;

  // real/gps 模式下，仅在用户显式点"开始"后才喂计时器（修复"自顾自演示"）。
  bool _perfUserArmed = false;

  // GPS 快乐表源（可由测试注入 Fake）
  GpsDataSource? gpsSource;
  StreamSubscription<GpsFrame>? _gpsSub;
  StreamSubscription<double>? _gpsAccelSub;
  late GpsVirtualDrivetrain _gpsDrivetrain;
  final GForceEstimator _gpsG = GForceEstimator();
  bool _gpsLive = false;
  bool _gpsValid = false;
  double? _pendingAccel;

  /// 数据源模式：'demo' 本地模拟 / 'real' 真实 OBD / 'gps' 纯 GPS 快乐表。
  String dataMode = 'demo';
  bool get isDemoMode => dataMode == 'demo';
  bool get isRealMode => dataMode == 'real';
  bool get isGpsMode => dataMode == 'gps';
  bool get isOffline => dataMode == 'demo';

  /// 真实帧是否在线（real 模式专用）：收到 OBD 帧 true，断开 false。
  bool _obdLive = false;

  /// 游戏 UDP 帧是否在线（game 源专用）。
  bool _gameLive = false;
  bool get gameLive => _gameLive;

  /// 手动档位覆盖（蓝牙手柄拨片；仅 gps/game 模式生效）。
  int? _manualGear;
  int? get manualGear => _manualGear;

  /// 最近一帧 GPS 经纬度（赛道自动计圈用；无定位为 null）。
  double? lastLat;
  double? lastLng;

  /// demo → DemoEngine 是否在跑；real → 真实帧是否在线；gps → GPS 帧是否在线。
  bool get connected => switch (dataMode) {
        'demo' => _demo.isRunning,
        'real' => _obdLive,
        'gps' => _gpsLive,
        _ => false,
      };

  double _speedFactor = 1.0;
  bool redFlash = true;
  bool demoReport = false; // 演示模式是否也上报看板（默认否，仅真车上报）

  // 行程
  double _tripKm = 0, _tripFuel = 0, _tripSec = 0;
  int _lastTs = -1;
  double get tripKm => _tripKm;
  double get tripFuel => _tripFuel;
  double get tripSec => _tripSec;

  // 数据丢失
  int _lastFrameMs = 0;
  bool _dataLost = false;

  ObdData _current = ObdData.empty;
  ObdData get current => _current;

  Future<void> init() async {
    await AppStore.instance.load();
    _speedFactor = await AppStore.instance.getSpeedFactor();
    redFlash = await AppStore.instance.getRedFlash();
    demoReport = await AppStore.instance.getDemoReport();
    final pid = await AppStore.instance.getProfile();
    if (pid != null) _profile = VehicleProfile.byId(pid);
    _demo = DemoEngine(_profile);
    _perf.restoreBest(
      best100: AppStore.instance.best100,
      best400: AppStore.instance.best400,
      bestBrake: AppStore.instance.bestBrake,
    );
    final mode = await AppStore.instance.getDataMode();
    dataMode = (mode == 'real' || mode == 'gps') ? mode : 'demo';
    if (dataMode == 'demo') {
      startDemo();
    } else if (dataMode == 'gps') {
      await _startGpsSource();
    } else {
      // real：进入等待连接，不启动 DemoEngine，绝不回灌演示数据。
      _obdLive = false;
      _dataLost = false;
      _current = ObdData(
        connected: false,
        source: 'obd',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    }
  }

  /// 切换数据源模式。mode：'demo' / 'real' / 'gps'。
  /// 同一时刻只活一个数据源：切走即停前一个。
  Future<GpsPermissionStatus> selectMode(String mode) async {
    final m = (mode == 'real' || mode == 'gps') ? mode : 'demo';
    dataMode = m;
    _perfDemoActive = false;
    _perfUserArmed = false;
    _perf.reset();
    await resetTrip();
    _dataLost = false;
    // 先停掉所有数据源
    _demo.stop();
    _demo.removeListener(_onFrame);
    await _stopGpsSource();
    _obdLive = false;

    if (m == 'demo') {
      _demo.start();
      _demo.addListener(_onFrame);
    } else if (m == 'gps') {
      final st = await _startGpsSource();
      // 无论权限如何都停留在 gps 模式：未授权/未开服务时 UI 给出引导，
      // 帧数为无效（速度 0 / --），绝不闪退。
      _current = ObdData(
        connected: false,
        source: 'gps',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await AppStore.instance.setDataMode(m);
      notifyListeners();
      return st;
    } else {
      // real：置等待连接空帧。
      _current = ObdData(
        connected: false,
        source: 'obd',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      _lastTs = -1;
    }
    await AppStore.instance.setDataMode(m);
    notifyListeners();
    return GpsPermissionStatus.ok;
  }

  /// 启动 GPS 快乐表数据源（权限检查 + 订阅帧）。
  Future<GpsPermissionStatus> _startGpsSource() async {
    gpsSource ??= GpsSpeedService();
    final st = await gpsSource!.ensurePermission();
    if (st != GpsPermissionStatus.ok) {
      _gpsLive = false;
      return st;
    }
    _gpsSub?.cancel();
    _gpsAccelSub?.cancel();
    _gpsSub = gpsSource!.frames.listen(onGpsFrame);
    _gpsAccelSub =
        gpsSource!.longitudinalAccelMss.listen((a) => _pendingAccel = a);
    await gpsSource!.start();
    _gpsG.reset();
    return st;
  }

  Future<void> _stopGpsSource() async {
    _gpsLive = false;
    await _gpsSub?.cancel();
    await _gpsAccelSub?.cancel();
    _gpsSub = null;
    _gpsAccelSub = null;
    try {
      await gpsSource?.stop();
    } catch (_) {}
  }

  void setProfile(VehicleProfile p) {
    _profile = p;
    _gpsDrivetrain = GpsVirtualDrivetrain(p);
    _coast = CoastStateMachine(idleRpm: p.idleRpm.toDouble());
    // 切车型若发生在受控性能测试中，先解除武装，避免新 DemoEngine
    // 丢失完成回调而卡在 running。
    _perfDemoActive = false;
    _perfUserArmed = false;
    _perf.reset();
    resetTrip();
    if (isOffline) {
      _demo.stop();
      _demo = DemoEngine(p);
      _demo.addListener(_onFrame);
      _demo.start();
    }
    AppStore.instance.setProfile(p.id);
    notifyListeners();
  }

  void setSpeedFactor(double f) {
    _speedFactor = f;
    AppStore.instance.setSpeedFactor(f);
  }

  double get speedFactor => _speedFactor;

  void setRedFlash(bool v) {
    redFlash = v;
    AppStore.instance.setRedFlash(v);
    notifyListeners();
  }

  void setDemoReport(bool v) {
    demoReport = v;
    AppStore.instance.setDemoReport(v);
    notifyListeners();
  }

  /// 当前帧是否应上报车队看板（需登录由上层 cloud 定时器门控）：
  /// demo → 仅当手动开启"演示也上报"；real → 真实 OBD 帧在线；
  /// gps → GPS 定位有效（速度解可用）时上报，source='gps'。
  bool get shouldReportToCloud {
    if (_current.dataLost) return false;
    if (dataMode == 'demo') return demoReport;
    if (dataMode == 'gps') {
      return _gpsLive && _current.source == 'gps' && _gpsValid;
    }
    return _obdLive && _current.source == 'obd';
  }

  void startDemo() {
    dataMode = 'demo';
    _obdLive = false;
    _dataLost = false;
    _perfDemoActive = false;
    resetTrip();
    _demo.removeListener(_onFrame);
    _demo.start();
    _demo.addListener(_onFrame);
    notifyListeners();
  }

  // 真实 OBD 数据源（连接成功后由 ObdService 推入原始帧）
  void onRealFrame(ObdData d) {
    // 优先级：OBD 连接成功自动切真实 OBD，停掉 GPS 源。
    if (dataMode == 'gps') {
      dataMode = 'real';
      _perfUserArmed = false;
      _perf.reset();
      _stopGpsSource();
    }
    _obdLive = true;
    _lastFrameMs = DateTime.now().millisecondsSinceEpoch;
    if (_dataLost) _dataLost = false;
    _enrich(d);
  }

  /// GPS 快乐表帧入口：纯手机 GPS，无 OBD。
  /// OBD 专有 PID 一律保持 null（严禁造假）；仅给 speed/altitude/heading，
  /// 并按车型齿比反推虚拟档位与转速（界面标注"估算/虚拟"）。
  void onGpsFrame(GpsFrame f) {
    _gpsLive = true;
    _lastFrameMs = DateTime.now().millisecondsSinceEpoch;
    _gpsValid = f.valid;
    lastLat = f.lat;
    lastLng = f.lng;
    if (_dataLost) _dataLost = false;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 静止死区：有效但低速（<3km/h，GPS 漂移 / 挪车）一律按 0 处理，
    // 避免静止时速度/转速在 0~几 km/h 之间抖动跳档。
    var speed = f.valid ? f.speedKmh : 0.0;
    if (speed < 3.0) speed = 0.0;

    double rpm;
    int gear;
    if (f.valid) {
      rpm = _gpsDrivetrain.update(speed);
      gear = _gpsDrivetrain.gear;
    } else {
      // 无效解（室内 / 定位关 / speed=-1 / 精度差）：速度稳 0、回空档、怠速，
      // 复位 G 估计器，避免把「上一帧速度 → 0」的差误当加减速。
      _gpsG.reset();
      rpm = _profile.idleRpm.toDouble();
      gear = 0;
    }
    if (_pendingAccel != null) {
      _gpsG.feedAccelMss(_pendingAccel!);
      _pendingAccel = null;
    }
    final g = _gpsG.feedGpsSpeed(speed, now);
    final raw = ObdData(
      connected: true,
      source: 'gps',
      speed: speed,
      rpm: rpm.round(),
      gear: gear,
      altitude: f.altitudeM,
      heading: f.heading,
      speedAccuracy: f.speedAccuracyM,
      accelG: g,
      // 其余 OBD 专有字段保持 null：水温/电压/机油温/进气温度/MAP/MAF/
      // 负荷/油门/油位 一律无数据源，皮肤按 null 显示 "--" 或隐藏。
    );
    _enrich(raw);
  }

  /// 游戏 UDP 帧入口：游戏直接下发转速/车速/档位，无需 OBD。
  /// 其余 OBD 专有字段保持 null（水温/电压等游戏不下发就显示 --）。
  void onGameFrame(GameTelemetry g) {
    _gameLive = true;
    _lastFrameMs = DateTime.now().millisecondsSinceEpoch;
    if (_dataLost) _dataLost = false;
    final raw = ObdData(
      connected: true,
      source: 'game',
      rpm: g.rpm.round(),
      speed: g.speedKmh,
      gear: g.gear,
      throttle: g.throttle,
    );
    _enrich(raw);
  }

  /// 停止游戏 UDP 源（UI 关闭监听时调用）。
  void stopGameSource() {
    _gameLive = false;
  }

  /// 蓝牙手柄拨片：手动加减挡（仅 gps/game 模式生效，夹在 -1..maxGear）。
  void nudgeGear(int delta, {int maxGear = 8}) {
    final base = _manualGear ?? _current.gear;
    var next = base + delta;
    if (next < -1) next = -1;
    if (next > maxGear) next = maxGear;
    _manualGear = next;
    notifyListeners();
  }

  /// 清除手动档位覆盖（恢复按车速/游戏自动档位）。
  void clearManualGear() {
    _manualGear = null;
    notifyListeners();
  }

  /// 真实连接意外断开：保持 real 模式（不回退演示），仅标记离线。
  void onObdDisconnected() {
    if (dataMode != 'real') return;
    _obdLive = false;
    _dataLost = false;
    _current = _current.copyWith(connected: false);
    notifyListeners();
  }

  void _onFrame() => _enrich(_demo.current);

  void _enrich(ObdData raw) {
    var d = raw;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 速度校准
    if (_speedFactor != 1.0) {
      d = d.copyWith(speed: d.speed * _speedFactor);
    }

    // 档位：演示源直接给；真实 OBD 按速比反推；GPS 已在 onGpsFrame 里
    // 按车型齿比反推好虚拟档位，这里不再覆盖。
    var gear = d.gear;
    if (d.source == 'obd') {
      gear = _profile.estimateGear(d.rpm.toDouble(), d.speed);
    }
    // 蓝牙手柄手动覆盖优先（仅 gps/game 模拟源；真实 OBD 以 ECU 为准）。
    if (_manualGear != null &&
        (d.source == 'gps' || d.source == 'game')) {
      gear = _manualGear!;
    }

    // 速度密度法补 MAF / 海拔
    var maf = d.maf;
    maf ??= FuelCalc.mafFromMap(
        d.map, d.rpm.toDouble(), d.intakeTemp, _profile.displacementL);
    final alt = d.altitude ?? FuelCalc.altitudeFromMap(d.map);

    // 行程积分（限制单帧 dt，防切后台灌入）
    final ts = now;
    if (_lastTs < 0) _lastTs = ts;
    var dt = (ts - _lastTs) / 1000.0;
    if (dt > 0 && dt < 5) {
      _tripSec += dt;
      _tripKm += d.speed / 3600.0 * dt;
      final lph = maf == null ? null : maf * 0.3401;
      if (lph != null) _tripFuel += lph / 3600.0 * dt;
    }
    _lastTs = ts;

    final enriched = d.copyWith(
      maf: maf,
      altitude: alt,
      gear: gear,
      tripKm: _tripKm,
      tripFuel: _tripFuel,
      tripSec: _tripSec,
      timestamp: now,
    );

    // 性能计时：
    //  - demo：仅受控测试场景激活时计时；
    //  - real/gps：仅在用户显式点"开始"后才计时（未点绝不自顾自跑），
    //    用真实车速/位移积分；完成时自动持久化最佳成绩。
    final userDriven = dataMode != 'demo';
    final perfActive = _perfDemoActive || (userDriven && _perfUserArmed);
    if (perfActive) {
      final before = _perf.snapshot.state;
      _perf.update(enriched.speed, dt.clamp(0.0, 0.5),
          userDriven: userDriven);
      if (before != PerfState.done && _perf.snapshot.state == PerfState.done) {
        persistPerfBests();
      }
    }

    _current = enriched;
    _lastFrameMs = now;
    notifyListeners();

    // coast 状态机：按 (车速, 转速) 语义区分 红灯停车 / 真熄火 / 熄火后重开新段。
    // demo 为受控模拟，不参与熄火落盘。
    if (dataMode != 'demo') {
      _handleCoastEvent(
          _coast.update(enriched.speed, enriched.rpm.toDouble(), now));
    }

    // 模拟声浪：所有模式（real/gps/demo）统一喂同一 rpm；gps 即按齿比
    // 反推的虚拟转速。平台层自己判熄火/duck，异常静默，绝不影响数据流。
    try {
      EngineSoundService.instance.feedFrame(enriched.rpm.toDouble(), now);
    } catch (_) {}
  }

  /// 处理 coast 状态机产出的动作。
  void _handleCoastEvent(CoastEvent e) {
    switch (e) {
      case CoastEvent.endTrip:
        // 真熄火：把当前行程落盘结束（静默，不弹 UI、不打扰）。
        resetTrip();
        break;
      case CoastEvent.beginNewTrip:
        // 熄火后又动起来 / 转速恢复：静默开一个新行程段（累加器清零；
        // 旧段已在 endTrip 落盘）。
        _tripKm = _tripFuel = _tripSec = 0;
        _lastTs = -1;
        notifyListeners();
        break;
      case CoastEvent.none:
        break;
    }
  }

  /// 心跳：real/gps 模式下检测数据丢失。
  ///  - >2s 无有效帧：归零动态读数（转速/燃油/负荷），但保留行程；
  ///  - >6s 仍无帧：按「转速≈0」喂 coast 状态机，由其确认真熄火并落盘结束行程。
  /// 红灯停车时帧持续到来（gap 很小），不会走到熄火分支。
  void checkStale() {
    if (dataMode == 'demo') return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final gap = now - _lastFrameMs;
    if (gap > 2000 && !_dataLost) {
      _dataLost = true;
      _current = _current.zeroedForDataLost();
      notifyListeners();
    }
    if (gap > 6000) {
      _handleCoastEvent(_coast.update(0, 0, now));
      // 声浪同步视为熄火，淡出停声。
      try {
        EngineSoundService.instance.feedFrame(0, now);
      } catch (_) {}
    }
  }

  // ---- 行程 ----
  Future<TripRec> resetTrip() async {
    final rec = TripRec(
      ts: DateTime.now().millisecondsSinceEpoch,
      km: _tripKm,
      fuel: _tripFuel,
      sec: _tripSec,
    );
    if (rec.km > 0.01 || rec.sec >= 10) {
      await AppStore.instance.addTrip(rec);
    }
    _tripKm = _tripFuel = _tripSec = 0;
    _lastTs = -1;
    notifyListeners();
    return rec;
  }

  // ---- 性能 ----
  void setPerfMode(int mode) {
    if (mode == _perf.snapshot.mode) return;
    _perfDemoActive = false;
    _perfUserArmed = false;
    _demo.cancelPerfScenario();
    _perf.setMode(mode);
    notifyListeners();
  }

  /// real/gps 模式：用户显式点"开始"。此前计时器绝不自动启动。
  /// mode=0 加速（建议静止起步）；mode=1 刹车（通常已在高速，一经按下即积分）。
  void beginPerfByUser(int mode) {
    if (mode == 0) {
      _perf.beginAccelByUser();
    } else {
      _perf.beginBrakeByUser(_current.speed);
    }
    _perfUserArmed = true;
    notifyListeners();
  }

  /// real/gps 模式：用户随时手动结束并落最佳成绩。
  void stopPerfByUser() {
    _perf.endByUser();
    if (_perf.snapshot.state == PerfState.done) persistPerfBests();
    notifyListeners();
  }

  /// 演示模式下：立即按所选项目（零百/刹车）触发性能测试场景。
  void startPerfScenario(int mode) {
    _perf.setMode(mode);
    _perf.reset(); // 每次都从待命重新开始，避免卡在 running/done 不响应
    if (isOffline) {
      _perfDemoActive = true;
      _demo.onPerfComplete = _onPerfScenarioComplete;
      _demo.runPerfScenario(mode);
    }
    notifyListeners();
  }

  /// 受控场景跑完（车停稳）：解除武装，保存最佳成绩。
  void _onPerfScenarioComplete() {
    _perfDemoActive = false;
    persistPerfBests();
    notifyListeners();
  }

  void resetPerf() {
    _perfDemoActive = false;
    _perfUserArmed = false;
    _demo.cancelPerfScenario();
    _perf.reset();
    notifyListeners();
  }

  /// 性能测试结束后持久化最佳成绩
  Future<void> persistPerfBests() async {
    final s = _perf.snapshot;
    await AppStore.instance.recordBest(s.best100, s.best400, s.bestBrake);
  }

  void stop() {
    _demo.stop();
    _stopGpsSource();
  }

  bool _disposed = false;
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _demo.dispose();
    _stopGpsSource();
    super.dispose();
  }
}
