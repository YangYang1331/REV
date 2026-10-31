import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obd_dashboard/core/fuel/fuel_log.dart';
import 'package:obd_dashboard/core/garage/garage.dart';

class TripRec {
  const TripRec({
    required this.ts,
    required this.km,
    required this.fuel,
    required this.sec,
    this.maxSpeed = 0,
    this.harshAccel = 0,
    this.harshBrake = 0,
    this.idleSec = 0,
    this.violations = 0,
    this.track = const [],
    this.vehicleId = '',
  });
  final int ts;
  final double km;
  final double fuel;
  final double sec;

  /// 所属车辆（多车车库 id；空串是老数据，归当前车辆）。
  final String vehicleId;

  /// 本段最高车速（km/h）。
  final double maxSpeed;

  /// 急加速 / 急减速次数（|纵向 G| ≥ 0.25g 计数）。
  final int harshAccel;
  final int harshBrake;

  /// 怠速时长（车速 <3km/h 且转速 >400 的秒数）。
  final double idleSec;

  /// 本段超速报警次数。
  final int violations;

  /// GPS 轨迹：`[lat, lng, speed]`，最多 300 点。
  final List<List<double>> track;

  double get avgSpeed => sec > 0 ? km / (sec / 3600.0) : 0;
  double? get l100 => km > 0.05 ? fuel / km * 100.0 : null;

  /// 驾驶评分（0–100）：急加速/急刹/怠速占比/超速扣分，里程太短不给分。
  int? get score {
    if (km < 0.3 || sec < 30) return null;
    var s = 100.0;
    s -= harshAccel * 3.0;
    s -= harshBrake * 4.0;
    final idleRatio = sec > 0 ? idleSec / sec : 0.0;
    if (idleRatio > 0.4) s -= (idleRatio - 0.4) * 60.0;
    s -= violations * 2.0;
    final avg = avgSpeed;
    if (avg > 110) s -= 5.0;
    return s.clamp(0, 100).round();
  }

  String get scoreLabel {
    final s = score;
    if (s == null) return '--';
    if (s >= 90) return '优秀';
    if (s >= 75) return '良好';
    if (s >= 60) return '一般';
    return '偏激烈';
  }

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'km': km,
        'fuel': fuel,
        'sec': sec,
        if (maxSpeed > 0) 'maxSpeed': maxSpeed,
        if (harshAccel > 0) 'ha': harshAccel,
        if (harshBrake > 0) 'hb': harshBrake,
        if (idleSec > 0) 'idle': idleSec,
        if (violations > 0) 'viol': violations,
        if (track.isNotEmpty) 'track': track,
        if (vehicleId.isNotEmpty) 'veh': vehicleId,
      };
  factory TripRec.fromJson(Map<String, dynamic> j) => TripRec(
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        km: (j['km'] as num?)?.toDouble() ?? 0,
        fuel: (j['fuel'] as num?)?.toDouble() ?? 0,
        sec: (j['sec'] as num?)?.toDouble() ?? 0,
        maxSpeed: (j['maxSpeed'] as num?)?.toDouble() ?? 0,
        harshAccel: (j['ha'] as num?)?.toInt() ?? 0,
        harshBrake: (j['hb'] as num?)?.toInt() ?? 0,
        idleSec: (j['idle'] as num?)?.toDouble() ?? 0,
        violations: (j['viol'] as num?)?.toInt() ?? 0,
        vehicleId: j['veh'] as String? ?? '',
        track: (j['track'] as List?)
                ?.whereType<List>()
                .map((e) => e
                    .map((v) => (v as num).toDouble())
                    .toList(growable: false))
                .toList(growable: false) ??
            const [],
      );
}

/// 本地持久化：最佳成绩 + 历史行程 + 设置，SharedPreferences（JSON）。
class AppStore {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const _kTrips = 'rev_trips';
  static const _kBest100 = 'rev_best100';
  static const _kBest400 = 'rev_best400';
  static const _kBestBrake = 'rev_bestbrake';
  static const _kSkin = 'rev_skin';
  static const _kProfile = 'rev_profile';
  static const _kSpeedFactor = 'rev_speed_factor';
  static const _kAwake = 'rev_awake';
  static const _kRedFlash = 'rev_redflash';
  static const _kDemoReport = 'rev_demo_report';
  static const _kKnownDevId = 'rev_known_dev_id';
  static const _kKnownDevName = 'rev_known_dev_name';
  static const _kTileOrder = 'rev_tile_order';
  static const _kTileModules = 'rev_tile_modules';
  static const _kPreheatAck = 'rev_preheat_ack';
  static const _kSoundEnabled = 'rev_sound_enabled';
  static const _kEngineSoundEnabled = 'rev_engine_sound_enabled';
  static const _kEnginePack = 'rev_engine_pack';
  static const _kEngineAudioQuality = 'rev_audio_quality';
  static const _kEngineProfileId = 'rev_engine_profile';
  static const _kEngineTuning = 'rev_engine_tuning';
  static const _kDataMode = 'rev_data_mode';
  static const _kHorizonFx = 'rev_horizon_fx';
  static const _kVideoSplash = 'rev_video_splash';
  static const _kGearMap = 'rev_gear_shift_map';
  static const _kOledPowerSave = 'rev_oled_power_save';
  static const _kSpeedLimitKmh = 'rev_speed_limit_kmh';
  static const _kPrivacyConsent = 'rev_privacy_consent';
  static const _kGpsUpload = 'rev_gps_upload';
  static const _kCloudUpload = 'rev_cloud_upload';
  static const _kLastVin = 'rev_last_vin';
  static const _kGarage = 'rev_garage';
  static const _kActiveVehicle = 'rev_active_vehicle';
  static const _kFuel = 'rev_fuel';

  /// 隐私政策版本：用户同意的版本号必须 >= 该值才会放行。
  /// 条款有实质变化时 +1，老用户会被重新询问一次。
  static const int privacyVersion = 1;

  /// GPS 轨迹是否随帧上传（敏感个人信息，默认关，需单独同意）。
  static bool gpsUpload = false;

  /// 是否允许把车辆数据上报到云端看板（默认开；"仅本地使用"时关）。
  static bool cloudUpload = true;

  /// 地平线动效同步缓存：进仪表盘皮肤/开屏时同步读取，避免每次异步等待。
  /// 默认 true；在 [load] 中从本地恢复，[setHorizonFx] 写入时同步更新。
  static bool horizonFx = true;

  /// 开屏动画同步缓存：默认 true（通电仪表自检扫针 → REV 定版自绘序列）。
  /// 关闭时开屏直接进 DashboardScreen，不播任何动画。
  /// prefs key 沿用 rev_video_splash（v2.11.0 起语义改为"是否播放开屏动画"）。
  /// 在 [load] 中从本地恢复，[setVideoSplash] 写入时同步更新。
  static bool videoSplash = true;

  SharedPreferences? _p;
  Future<SharedPreferences> get _prefs async =>
      _p ??= await SharedPreferences.getInstance();

  // ---- 最佳成绩 ----
  double? best100;
  double? best400;
  double? bestBrake;

  Future<void> load() async {
    final p = await _prefs;
    best100 = p.getDouble(_kBest100);
    best400 = p.getDouble(_kBest400);
    bestBrake = p.getDouble(_kBestBrake);
    horizonFx = p.getBool(_kHorizonFx) ?? true;
    videoSplash = p.getBool(_kVideoSplash) ?? true;
    gpsUpload = p.getBool(_kGpsUpload) ?? false;
    cloudUpload = p.getBool(_kCloudUpload) ?? true;
  }

  // ---- 隐私 / 数据授权 ----
  /// 已同意的隐私政策版本；未同意返回 0。
  Future<int> getPrivacyConsent() async =>
      (await _prefs).getInt(_kPrivacyConsent) ?? 0;

  Future<bool> getPrivacyAccepted() async =>
      (await getPrivacyConsent()) >= privacyVersion;

  Future<void> setPrivacyConsent(int version) async =>
      (await _prefs).setInt(_kPrivacyConsent, version);

  Future<bool> getGpsUpload() async =>
      (await _prefs).getBool(_kGpsUpload) ?? false;

  Future<void> setGpsUpload(bool v) async {
    gpsUpload = v;
    await (await _prefs).setBool(_kGpsUpload, v);
  }

  Future<bool> getCloudUpload() async =>
      (await _prefs).getBool(_kCloudUpload) ?? true;

  Future<void> setCloudUpload(bool v) async {
    cloudUpload = v;
    await (await _prefs).setBool(_kCloudUpload, v);
  }

  Future<String?> getLastVin() async => (await _prefs).getString(_kLastVin);
  Future<void> setLastVin(String vin) async =>
      (await _prefs).setString(_kLastVin, vin);

  /// 更新最佳成绩，返回是否刷新纪录
  Future<bool> recordBest(
      double? t100, double? t400, double? brake) async {
    var broke = false;
    final p = await _prefs;
    if (t100 != null && (best100 == null || t100 < best100!)) {
      best100 = t100;
      await p.setDouble(_kBest100, t100);
      broke = true;
    }
    if (t400 != null && (best400 == null || t400 < best400!)) {
      best400 = t400;
      await p.setDouble(_kBest400, t400);
      broke = true;
    }
    if (brake != null && (bestBrake == null || brake < bestBrake!)) {
      bestBrake = brake;
      await p.setDouble(_kBestBrake, brake);
      broke = true;
    }
    return broke;
  }

  // ---- 行程 ----
  Future<List<TripRec>> loadTrips() async {
    final p = await _prefs;
    final raw = p.getString(_kTrips);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TripRec.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 存档一段行程（清零前调用）；忽略无意义空行程。
  Future<void> addTrip(TripRec rec) async {
    if (rec.km <= 0.01 && rec.sec < 10) return;
    final trips = await loadTrips();
    trips.insert(0, rec);
    if (trips.length > 100) trips.removeRange(100, trips.length);
    final p = await _prefs;
    await p.setString(_kTrips,
        jsonEncode(trips.map((t) => t.toJson()).toList()));
    // 累计里程：保养提醒靠它推算"距离上次保养又跑了多少"。
    try {
      final accum = (p.getDouble(_kOdoAccum) ?? 0) + rec.km;
      await p.setDouble(_kOdoAccum, accum);
    } catch (_) {}
  }

  Future<void> clearTrips() async {
    final p = await _prefs;
    await p.remove(_kTrips);
  }

  /// 整体覆盖行程列表（合并 / 拆分 / 删除后调用）。
  Future<void> saveTrips(List<TripRec> trips) async {
    final p = await _prefs;
    await p.setString(_kTrips,
        jsonEncode(trips.map((t) => t.toJson()).toList()));
  }

  // ---- 加油记录 ----
  Future<List<FuelRec>> loadFuelRecords() async {
    final raw = (await _prefs).getString(_kFuel);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FuelRec.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveFuelRecords(List<FuelRec> recs) async {
    final p = await _prefs;
    await p.setString(_kFuel,
        jsonEncode(recs.map((r) => r.toJson()).toList()));
  }

  // ---- 多车车库 ----
  Future<List<GarageVehicle>> loadGarage() async {
    final raw = (await _prefs).getString(_kGarage);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => GarageVehicle.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGarage(List<GarageVehicle> vehicles) async =>
      (await _prefs).setString(
          _kGarage, jsonEncode(vehicles.map((v) => v.toJson()).toList()));

  Future<String?> getActiveVehicleId() async =>
      (await _prefs).getString(_kActiveVehicle);

  Future<void> setActiveVehicleId(String id) async =>
      (await _prefs).setString(_kActiveVehicle, id);

  /// 保证车库至少有一辆车：老用户从当前车型档案 + 上次 VIN 迁移一辆。
  Future<List<GarageVehicle>> ensureGarage() async {
    var list = await loadGarage();
    if (list.isEmpty) {
      final profile = await getProfile() ?? 'mazda6_2011';
      final vin = await getLastVin() ?? '';
      final v = GarageVehicle(
        id: GarageVehicle.newId(),
        name: '我的车',
        profileId: profile,
        vin: vin,
        createdTs: DateTime.now().millisecondsSinceEpoch,
      );
      list = [v];
      await saveGarage(list);
      await setActiveVehicleId(v.id);
      return list;
    }
    final active = await getActiveVehicleId();
    if (active == null || !list.any((e) => e.id == active)) {
      await setActiveVehicleId(list.first.id);
    }
    return list;
  }

  /// 当前车辆；车库为空时返回 null。
  Future<GarageVehicle?> getActiveVehicle() async {
    final list = await ensureGarage();
    final id = await getActiveVehicleId();
    for (final v in list) {
      if (v.id == id) return v;
    }
    return list.isEmpty ? null : list.first;
  }

  // ---- 设置 ----
  Future<String?> getSkin() async => (await _prefs).getString(_kSkin);
  Future<void> setSkin(String id) async =>
      (await _prefs).setString(_kSkin, id);

  Future<String?> getProfile() async => (await _prefs).getString(_kProfile);
  Future<void> setProfile(String id) async =>
      (await _prefs).setString(_kProfile, id);

  Future<double> getSpeedFactor() async =>
      (await _prefs).getDouble(_kSpeedFactor) ?? 1.0;
  Future<void> setSpeedFactor(double v) async =>
      (await _prefs).setDouble(_kSpeedFactor, v);

  Future<bool> getAwake() async => (await _prefs).getBool(_kAwake) ?? true;
  Future<void> setAwake(bool v) async => (await _prefs).setBool(_kAwake, v);

  Future<bool> getRedFlash() async =>
      (await _prefs).getBool(_kRedFlash) ?? true;
  Future<void> setRedFlash(bool v) async =>
      (await _prefs).setBool(_kRedFlash, v);

  /// 演示模式是否同步到车队看板。默认 true：登录后演示数据自动同步（仅自己账号可见、
  /// 看板标注"演示"）；未登录时由上报定时器的登录门控拦截，不会发出。
  Future<bool> getDemoReport() async =>
      (await _prefs).getBool(_kDemoReport) ?? true;
  Future<void> setDemoReport(bool v) async =>
      (await _prefs).setBool(_kDemoReport, v);

  // ---- 已配对 / 记忆的 OBD 设备（自动连接）----
  Future<String?> getKnownDeviceId() async =>
      (await _prefs).getString(_kKnownDevId);
  Future<String?> getKnownDeviceName() async =>
      (await _prefs).getString(_kKnownDevName);
  Future<void> setKnownDevice(String id, String name) async {
    final p = await _prefs;
    await p.setString(_kKnownDevId, id);
    await p.setString(_kKnownDevName, name);
  }

  Future<void> clearKnownDevice() async {
    final p = await _prefs;
    await p.remove(_kKnownDevId);
    await p.remove(_kKnownDevName);
  }

  // ---- 可编辑磁贴看板 ----
  /// 默认显示的磁贴模块 id（顺序即默认布局顺序）。
  static const List<String> defaultTileModules = [
    'speed', 'rpm', 'gear', 'coolant', 'voltage', 'boost', 'load',
    'throttle', 'maf', 'fuelRate', 'fuelLevel', 'intakeTemp',
    'tripKm', 'tripFuel',
  ];

  Future<List<String>> getTileOrder() async {
    final raw = (await _prefs).getString(_kTileOrder);
    if (raw == null || raw.isEmpty) return List.of(defaultTileModules);
    try {
      final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
      return list.isEmpty ? List.of(defaultTileModules) : list;
    } catch (_) {
      return List.of(defaultTileModules);
    }
  }

  Future<void> setTileOrder(List<String> order) async =>
      (await _prefs).setString(_kTileOrder, jsonEncode(order));

  Future<List<String>> getTileModules() async {
    final raw = (await _prefs).getString(_kTileModules);
    if (raw == null || raw.isEmpty) return List.of(defaultTileModules);
    try {
      final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
      return list.isEmpty ? List.of(defaultTileModules) : list;
    } catch (_) {
      return List.of(defaultTileModules);
    }
  }

  Future<void> setTileModules(List<String> mods) async =>
      (await _prefs).setString(_kTileModules, jsonEncode(mods));

  // ---- 预热门引导（确认过即不再弹）----
  Future<bool> getPreheatAck() async =>
      (await _prefs).getBool(_kPreheatAck) ?? false;
  Future<void> setPreheatAck(bool v) async =>
      (await _prefs).setBool(_kPreheatAck, v);

  // ---- 音效反馈开关 ----
  Future<bool> getSoundEnabled() async =>
      (await _prefs).getBool(_kSoundEnabled) ?? true;
  Future<void> setSoundEnabled(bool v) async =>
      (await _prefs).setBool(_kSoundEnabled, v);

  /// 模拟声浪（随转速合成引擎音）独立开关，【默认关】避免扰民，
  /// 与全局音效开关 [_kSoundEnabled] 分开控制。
  Future<bool> getEngineSoundEnabled() async =>
      (await _prefs).getBool(_kEngineSoundEnabled) ?? false;
  Future<void> setEngineSoundEnabled(bool v) async =>
      (await _prefs).setBool(_kEngineSoundEnabled, v);

  /// 引擎声浪引擎（采样包 id），默认 "synth"（实时合成）。
  Future<String> getEnginePack() async =>
      (await _prefs).getString(_kEnginePack) ?? 'synth';
  Future<void> setEnginePack(String v) async =>
      (await _prefs).setString(_kEnginePack, v);

  /// 采样音质档：auto（默认）/ high / low。
  Future<String> getEngineAudioQuality() async =>
      (await _prefs).getString(_kEngineAudioQuality) ?? 'auto';
  Future<void> setEngineAudioQuality(String v) async =>
      (await _prefs).setString(_kEngineAudioQuality, v);

  /// 合成声浪的引擎型号（i4 / i6 / v6 / v8 / v10 / v12 / h4 / h6 / rotary）。
  Future<String> getEngineProfileId() async =>
      (await _prefs).getString(_kEngineProfileId) ?? 'i4';
  Future<void> setEngineProfileId(String v) async =>
      (await _prefs).setString(_kEngineProfileId, v);

  /// 合成声浪调音参数 JSON（亮度/低频/颗粒/回火），见 EngineTuning。
  Future<String> getEngineTuning() async =>
      (await _prefs).getString(_kEngineTuning) ?? '';
  Future<void> setEngineTuning(String v) async =>
      (await _prefs).setString(_kEngineTuning, v);

  // ---- 数据源模式（'demo' 本地模拟 / 'real' 真实 OBD，默认 demo）----
  Future<String> getDataMode() async =>
      (await _prefs).getString(_kDataMode) ?? 'demo';
  Future<void> setDataMode(String v) async =>
      (await _prefs).setString(_kDataMode, v);

  // ---- 地平线动效开关（开屏/进仪表盘一次性自检动效，默认开）----
  Future<bool> getHorizonFx() async =>
      (await _prefs).getBool(_kHorizonFx) ?? true;
  Future<void> setHorizonFx(bool v) async {
    horizonFx = v;
    await (await _prefs).setBool(_kHorizonFx, v);
  }

  // ---- 开屏动画开关（默认开：通电自检扫针 → REV 定版自绘序列；关则直接进主页）----
  Future<bool> getVideoSplash() async =>
      (await _prefs).getBool(_kVideoSplash) ?? true;
  Future<void> setVideoSplash(bool v) async {
    videoSplash = v;
    await (await _prefs).setBool(_kVideoSplash, v);
  }

  // ---- 手柄换挡键位映射（JSON）----
  Future<Map<String, dynamic>?> getGearMapJson() async {
    final raw = (await _prefs).getString(_kGearMap);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setGearMapJson(Map<String, dynamic> m) async =>
      (await _prefs).setString(_kGearMap, jsonEncode(m));

  // ---- OLED 省电（纯黑底/降刷新）----
  Future<bool> getOledPowerSave() async =>
      (await _prefs).getBool(_kOledPowerSave) ?? false;
  Future<void> setOledPowerSave(bool v) async =>
      (await _prefs).setBool(_kOledPowerSave, v);

  // ---- 限速提醒（手动设定 km/h；0=关）----
  Future<int> getSpeedLimitKmh() async =>
      (await _prefs).getInt(_kSpeedLimitKmh) ?? 0;
  Future<void> setSpeedLimitKmh(int v) async =>
      (await _prefs).setInt(_kSpeedLimitKmh, v);

  // ---- 报警配置 ----
  static const _kAlarmCfg = 'rev_alarm_cfg';

  Future<AlarmConfig> loadAlarmConfig() async {
    final raw = (await _prefs).getString(_kAlarmCfg);
    if (raw == null || raw.isEmpty) return const AlarmConfig();
    try {
      return AlarmConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AlarmConfig();
    }
  }

  Future<void> saveAlarmConfig(AlarmConfig c) async =>
      (await _prefs).setString(_kAlarmCfg, jsonEncode(c.toJson()));

  // ---- 保养提醒 ----
  static const _kMaint = 'rev_maintenance';
  static const _kOdoAccum = 'rev_odo_accum_km';

  /// App 记录到的累计里程（只要存过行程就累加，用于推算"距离上次保养又跑了多少"）。
  Future<double> getOdoAccumKm() async =>
      (await _prefs).getDouble(_kOdoAccum) ?? 0;

  Future<MaintState> loadMaintState() async {
    final raw = (await _prefs).getString(_kMaint);
    final accum = await getOdoAccumKm();
    if (raw == null || raw.isEmpty) return MaintState(accumKm: accum);
    try {
      return MaintState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>, accum);
    } catch (_) {
      return MaintState(accumKm: accum);
    }
  }

  Future<void> saveMaintState(MaintState s) async =>
      (await _prefs).setString(_kMaint, jsonEncode(s.toJson()));
}

/// 报警阈值配置（持久化）。
class AlarmConfig {
  const AlarmConfig({
    this.enabled = true,
    this.voice = true,
    this.sound = true,
    this.coolantHighC = 105,
    this.oilHighC = 130,
    this.voltageLowV = 11.8,
    this.voltageHighV = 15.2,
    this.speedLimitKmh = 0,
  });
  final bool enabled;
  final bool voice;
  final bool sound;
  final int coolantHighC;
  final int oilHighC;
  final double voltageLowV;
  final double voltageHighV;
  final int speedLimitKmh;

  Map<String, dynamic> toJson() => {
        'en': enabled,
        'voice': voice,
        'sound': sound,
        'cool': coolantHighC,
        'oil': oilHighC,
        'vlo': voltageLowV,
        'vhi': voltageHighV,
        'spd': speedLimitKmh,
      };

  factory AlarmConfig.fromJson(Map<String, dynamic> j) => AlarmConfig(
        enabled: j['en'] as bool? ?? true,
        voice: j['voice'] as bool? ?? true,
        sound: j['sound'] as bool? ?? true,
        coolantHighC: (j['cool'] as num?)?.toInt() ?? 105,
        oilHighC: (j['oil'] as num?)?.toInt() ?? 130,
        voltageLowV: (j['vlo'] as num?)?.toDouble() ?? 11.8,
        voltageHighV: (j['vhi'] as num?)?.toDouble() ?? 15.2,
        speedLimitKmh: (j['spd'] as num?)?.toInt() ?? 0,
      );
}

/// 保养状态：里程锚点 + 最近一次各项保养的里程/时间。
///
/// 车没有"总里程"这个标准 PID，所以用「用户填一次当前仪表里程 + App 自己累加
/// 行程里程」来推算，偏差随时间可控（每次用户再填一次就自动校准）。
class MaintState {
  const MaintState({
    this.accumKm = 0,
    this.odoAnchorKm,
    this.odoAnchorAccumKm = 0,
    this.lastOilOdoKm,
    this.lastTireOdoKm,
    this.lastInspectTs,
    this.lastInsuranceTs,
    this.intervalOilKm = 8000,
    this.intervalTireKm = 40000,
    this.intervalInspectDays = 365,
    this.intervalInsuranceDays = 365,
  });

  final double accumKm;
  final double? odoAnchorKm;
  final double odoAnchorAccumKm;
  final double? lastOilOdoKm;
  final double? lastTireOdoKm;
  final int? lastInspectTs;
  final int? lastInsuranceTs;
  final int intervalOilKm;
  final int intervalTireKm;
  final int intervalInspectDays;
  final int intervalInsuranceDays;

  /// 当前估算总里程（未填过锚点时为 null）。
  double? get currentOdoKm => odoAnchorKm == null
      ? null
      : odoAnchorKm! + (accumKm - odoAnchorAccumKm);

  double? get sinceOilKm {
    final odo = currentOdoKm;
    if (odo == null || lastOilOdoKm == null) return null;
    return odo - lastOilOdoKm!;
  }

  double? get sinceTireKm {
    final odo = currentOdoKm;
    if (odo == null || lastTireOdoKm == null) return null;
    return odo - lastTireOdoKm!;
  }

  int? get sinceInspectDays => lastInspectTs == null
      ? null
      : DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastInspectTs!))
          .inDays;

  int? get sinceInsuranceDays => lastInsuranceTs == null
      ? null
      : DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastInsuranceTs!))
          .inDays;

  /// 保险到期日（未记录时为 null）。
  DateTime? get insuranceDue => lastInsuranceTs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastInsuranceTs!)
          .add(Duration(days: intervalInsuranceDays));

  /// 年检到期日（未记录时为 null）。
  DateTime? get inspectDue => lastInspectTs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastInspectTs!)
          .add(Duration(days: intervalInspectDays));

  Map<String, dynamic> toJson() => {
        'anchor': odoAnchorKm,
        'anchorAccum': odoAnchorAccumKm,
        'oilOdo': lastOilOdoKm,
        'tireOdo': lastTireOdoKm,
        'inspectTs': lastInspectTs,
        'insTs': lastInsuranceTs,
        'iOil': intervalOilKm,
        'iTire': intervalTireKm,
        'iDays': intervalInspectDays,
        'iIns': intervalInsuranceDays,
      };

  factory MaintState.fromJson(Map<String, dynamic> j, double accum) => MaintState(
        accumKm: accum,
        odoAnchorKm: (j['anchor'] as num?)?.toDouble(),
        odoAnchorAccumKm: (j['anchorAccum'] as num?)?.toDouble() ?? 0,
        lastOilOdoKm: (j['oilOdo'] as num?)?.toDouble(),
        lastTireOdoKm: (j['tireOdo'] as num?)?.toDouble(),
        lastInspectTs: (j['inspectTs'] as num?)?.toInt(),
        lastInsuranceTs: (j['insTs'] as num?)?.toInt(),
        intervalOilKm: (j['iOil'] as num?)?.toInt() ?? 8000,
        intervalTireKm: (j['iTire'] as num?)?.toInt() ?? 40000,
        intervalInspectDays: (j['iDays'] as num?)?.toInt() ?? 365,
        intervalInsuranceDays: (j['iIns'] as num?)?.toInt() ?? 365,
      );

  MaintState copyWith({
    double? odoAnchorKm,
    double? odoAnchorAccumKm,
    double? lastOilOdoKm,
    double? lastTireOdoKm,
    int? lastInspectTs,
    int? lastInsuranceTs,
    int? intervalOilKm,
    int? intervalTireKm,
    int? intervalInspectDays,
    int? intervalInsuranceDays,
  }) =>
      MaintState(
        accumKm: accumKm,
        odoAnchorKm: odoAnchorKm ?? this.odoAnchorKm,
        odoAnchorAccumKm: odoAnchorAccumKm ?? this.odoAnchorAccumKm,
        lastOilOdoKm: lastOilOdoKm ?? this.lastOilOdoKm,
        lastTireOdoKm: lastTireOdoKm ?? this.lastTireOdoKm,
        lastInspectTs: lastInspectTs ?? this.lastInspectTs,
        lastInsuranceTs: lastInsuranceTs ?? this.lastInsuranceTs,
        intervalOilKm: intervalOilKm ?? this.intervalOilKm,
        intervalTireKm: intervalTireKm ?? this.intervalTireKm,
        intervalInspectDays: intervalInspectDays ?? this.intervalInspectDays,
        intervalInsuranceDays:
            intervalInsuranceDays ?? this.intervalInsuranceDays,
      );
}
