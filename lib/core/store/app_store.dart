import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TripRec {
  const TripRec({
    required this.ts,
    required this.km,
    required this.fuel,
    required this.sec,
  });
  final int ts;
  final double km;
  final double fuel;
  final double sec;

  double get avgSpeed => sec > 0 ? km / (sec / 3600.0) : 0;
  double? get l100 => km > 0.05 ? fuel / km * 100.0 : null;

  Map<String, dynamic> toJson() =>
      {'ts': ts, 'km': km, 'fuel': fuel, 'sec': sec};
  factory TripRec.fromJson(Map<String, dynamic> j) => TripRec(
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        km: (j['km'] as num?)?.toDouble() ?? 0,
        fuel: (j['fuel'] as num?)?.toDouble() ?? 0,
        sec: (j['sec'] as num?)?.toDouble() ?? 0,
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
  static const _kEnvSoundEnabled = 'rev_env_sound_enabled';
  static const _kDataMode = 'rev_data_mode';
  static const _kHorizonFx = 'rev_horizon_fx';
  static const _kVideoSplash = 'rev_video_splash';
  static const _kGearMap = 'rev_gear_shift_map';
  static const _kOledPowerSave = 'rev_oled_power_save';
  static const _kSpeedLimitKmh = 'rev_speed_limit_kmh';

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
  }

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
  }

  Future<void> clearTrips() async {
    final p = await _prefs;
    await p.remove(_kTrips);
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

  /// 环境声（风噪/胎噪，随车速）开关，默认开启。
  Future<bool> getEnvSoundEnabled() async =>
      (await _prefs).getBool(_kEnvSoundEnabled) ?? true;
  Future<void> setEnvSoundEnabled(bool v) async =>
      (await _prefs).setBool(_kEnvSoundEnabled, v);

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
}
