import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:open_filex/open_filex.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 云端服务：车辆数据上报（车队看板）+ GPS 轨迹 + 应用内更新。
/// 移植自原生 com.ghost.cluster.cloud.CloudUploader / GpsTracker / Updater。
///
/// 服务器地址【不硬编码】：
///  - 开源/默认构建：`defaultBase`/`defaultEndpoint` 为空，App 启动不自动上报，
///    用户须在设置里填自己部署的服务器地址。
///  - 自用构建：通过 `--dart-define=DEFAULT_BASE=... --dart-define=DEFAULT_ENDPOINT=...`
///    注入，行为与现状一致。
class CloudService {
  CloudService();

  /// 复用同一个 HttpClient：上报是 3 秒一次的高频请求，复用长连接可以省掉
  /// 每次 TLS 握手（移动网络下尤其明显），也避免句柄/端口堆积。
  HttpClient? _http;
  HttpClient get _client {
    final c = _http;
    if (c != null) return c;
    final n = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..idleTimeout = const Duration(seconds: 30);
    _http = n;
    return n;
  }

  /// 释放网络与定位资源（随 Provider 销毁调用）。
  void dispose() {
    _http?.close(force: true);
    _http = null;
    _posSub?.cancel();
    _posSub = null;
  }

  static const String defaultBase =
      String.fromEnvironment('DEFAULT_BASE', defaultValue: '');
  static const String defaultEndpoint =
      String.fromEnvironment('DEFAULT_ENDPOINT', defaultValue: '');
  static const _kEndpoint = 'cloud_endpoint';
  static const _kDeviceId = 'cloud_device_id';
  static const _kOfflineQueue = 'rev_offline_queue';
  static const _maxQueue = 200;

  String _endpoint = defaultEndpoint;
  String get endpoint => _endpoint;
  String get baseUrl => _endpoint.replaceAll(RegExp(r'/api/v1.*$'), '');

  /// 未配置服务器地址：设置页提示用户填写自己部署的地址。
  bool get needsUserServer => _endpoint.trim().isEmpty;

  String _deviceId = 'unknown';
  String get deviceId => _deviceId;

  // ---- 上报状态（设置页可见，用于自查"看板没数据"）----
  DateTime? _lastOkAt;
  String? _lastError;
  bool _lastUnauthorized = false;
  DateTime? get lastOkAt => _lastOkAt;
  String? get lastError => _lastError;
  bool get lastUnauthorized => _lastUnauthorized;

  /// 401（token 失效）回调：上层据此清登录态并提示重新登录。
  void Function()? onUnauthorized;

  void _noteOk() {
    _lastOkAt = DateTime.now();
    _lastError = null;
    _lastUnauthorized = false;
  }

  void _noteError(String e) {
    if (_lastUnauthorized) return;
    _lastError = e;
  }

  Position? _loc;
  bool _gpsStarted = false;
  bool _gpsRequesting = false;
  DateTime _lastGpsTry = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<Position>? _posSub;
  bool get gpsEnabled => _gpsStarted;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kEndpoint);
    // 地址优先级：用户已填 > 自用构建注入的默认值 > 空（不自动上报）。
    // 不做任何硬编码 IP/域名的迁移。
    _endpoint = (saved != null && saved.isNotEmpty)
        ? saved.trim()
        : defaultEndpoint;

    var did = prefs.getString(_kDeviceId);
    if (did == null || did.isEmpty) {
      did = 'rev-${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
      await prefs.setString(_kDeviceId, did);
    }
    _deviceId = did;
  }

  Future<void> setEndpoint(String v) async {
    _endpoint = v.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEndpoint, _endpoint);
  }

  // ── GPS ──
  /// 懒启动：只在真正需要上报时才开启，未登录/未连车时不后台定位。
  /// 失败后 10 分钟内不再重试，避免每隔 3 秒弹一次权限框。
  Future<bool> startGps() async {
    if (_gpsStarted) return true;
    if (_gpsRequesting) return false;
    if (DateTime.now().difference(_lastGpsTry).inMinutes < 10) return false;
    _lastGpsTry = DateTime.now();
    _gpsRequesting = true;
    try {
      bool ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // 5 米才回调一次：静止时不反复刷新定位，行车速度依旧连续。
          distanceFilter: 5,
        ),
      ).listen((p) => _loc = p, onError: (_) {});
      _gpsStarted = true;
      return true;
    } finally {
      _gpsRequesting = false;
    }
  }

  /// 上报一帧（实车/演示/游戏都上报；看板用 source 区分）。
  /// [token] 登录态：有则带 `Authorization: Bearer <token>`。
  /// 网络失败（非 401）帧进离线队列待补传；401 直接丢弃（清登录态由上层处理）。
  Future<void> report(ObdData d, {String? token}) async {
    final url = _endpoint.trim();
    if (url.isEmpty) return;
    // 只在真正上报时开启 GPS：未登录 / 未连车时不后台定位耗电。
    if (!_gpsStarted) unawaited(startGps());
    final map = _buildFrame(d);
    final r = await _postFrame(url, map, token);
    if (r == true) {
      await _maybeFlush(token);
    } else if (r == false) {
      await _enqueue(map);
    }
    // r == null 表示 401，不排队。
  }

  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);

  /// 离线补传节流：每 30 秒最多补一次，避免每帧成功后都整队重发。
  Future<void> _maybeFlush(String? token) async {
    final now = DateTime.now();
    if (now.difference(_lastFlush).inSeconds < 30) return;
    _lastFlush = now;
    await flushQueue(token: token);
  }

  Map<String, dynamic> _buildFrame(ObdData d) {
    final map = <String, dynamic>{
      'deviceId': _deviceId,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'source': d.source,
      'connected': d.connected,
      'speed': _round(d.speed),
      'rpm': d.rpm,
      'gear': d.gear < 0 ? null : d.gear,
      'coolant': _round(d.coolant),
      'oilTemp': _round(d.oilTemp),
      'intakeTemp': _round(d.intakeTemp),
      'ambient': _round(d.ambient),
      'voltage': _round(d.voltage),
      'boost': _round(d.boost),
      'load': _round(d.load),
      'throttle': _round(d.throttle),
      'fuelLevel': _round(d.fuelLevel),
      'maf': _round(d.maf, 2),
      'fuelLph': _round(d.fuelLph, 2),
      'fuelRate': _round(d.fuelL100, 2),
      'tripKm': _round(d.tripKm, 2),
      'tripFuel': _round(d.tripFuel, 3),
      'tripSec': _round(d.tripSec, 0),
    };
    if (_loc != null) {
      map['lat'] = _round(_loc!.latitude, 5);
      map['lng'] = _round(_loc!.longitude, 5);
      map['gpsSpeed'] = _round(_loc!.speed * 3.6);
      map['heading'] = _round(_loc!.heading);
    }
    return map;
  }

  /// 返回：true=成功(2xx)；false=网络错误/超时/5xx（可重试）；null=401（丢弃）。
  Future<bool?> _postFrame(String url, Map<String, dynamic> map,
      [String? token]) async {
    try {
      final req = await _client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      req.write(jsonEncode(map));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      final code = resp.statusCode;
      // 必须把响应体读完，连接才会回到连接池被复用；否则下次仍要重新握手。
      await resp.drain<void>();
      if (code == 401) {
        debugPrint('cloud report 401 (not logged in / token expired)');
        _lastUnauthorized = true;
        _lastError = '登录已过期，请重新登录';
        try {
          onUnauthorized?.call();
        } catch (_) {}
        return null;
      }
      if (code < 200 || code >= 300) {
        debugPrint('cloud report http $code');
        _noteError('服务器返回 HTTP $code');
        return false;
      }
      _noteOk();
      return true;
    } catch (e) {
      // 连接可能已损坏：丢弃并让下次重建，避免坏连接被反复复用。
      _http?.close(force: true);
      _http = null;
      debugPrint('cloud report failed: $e');
      _noteError('网络不可达：$e');
      return false;
    }
  }

  // ── 离线队列（FIFO，上限 200 帧）──
  Future<List<dynamic>> _readQueue() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kOfflineQueue);
      if (raw == null || raw.isEmpty) return [];
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<dynamic> q) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kOfflineQueue, jsonEncode(q));
    } catch (e) {
      debugPrint('offline queue write failed: $e');
    }
  }

  Future<void> _enqueue(Map<String, dynamic> frame) async {
    final q = await _readQueue();
    q.add(frame);
    while (q.length > _maxQueue) {
      q.removeAt(0); // FIFO 丢最旧
    }
    await _writeQueue(q);
  }

  /// 网络恢复 / 启动 / 登录后补传离线帧。需要 [token]（鉴权接口）。
  /// [maxFrames] 控制单轮补传条数，避免弱网时长时间占用。
  Future<void> flushQueue({String? token, int maxFrames = 50}) async {
    if (token == null || token.isEmpty) return;
    final url = _endpoint.trim();
    if (url.isEmpty) return;
    final q = await _readQueue();
    if (q.isEmpty) return;
    final remaining = [];
    var i = 0;
    for (; i < q.length; i++) {
      if (i >= maxFrames) break;
      final item = q[i];
      if (item is! Map<String, dynamic>) continue;
      final r = await _postFrame(url, item, token);
      if (r == true) continue;
      // 401 或网络错误：停止本轮补传，当前帧和后面全部保留
      remaining.add(item);
      i++;
      break;
    }
    remaining.addAll(q.sublist(i));
    await _writeQueue(remaining);
    if (remaining.length < q.length) {
      debugPrint('offline queue flushed: ${q.length - remaining.length} sent');
    }
  }

  /// 当前离线待补传帧数（供 UI 展示）。
  Future<int> pendingCount() async => (await _readQueue()).length;

  // ── 应用内更新 ──
  /// 返回 null 表示已是最新；否则返回 {versionCode,versionName,notes,apkUrl,...}。
  /// baseUrl 同时支持 https 域名与 IP:端口。开源版未配服务器时直接不检查。
  Future<Map<String, dynamic>?> checkUpdate(int currentCode) async {
    if (_endpoint.trim().isEmpty) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse('$baseUrl/api/v1/latest'));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      final rel = jsonDecode(body) as Map<String, dynamic>;
      final code = (rel['versionCode'] as num?)?.toInt() ?? 0;
      if (code <= currentCode) return null;
      return rel;
    } catch (e) {
      debugPrint('check update failed: $e');
      return null;
    }
  }

  /// Android 8+ 安装未知来源 APK 需要"安装其他应用"权限。
  /// 返回是否已授权；未授权时由 UI 引导用户去系统设置打开。
  Future<bool> ensureInstallPermission() async {
    try {
      var st = await Permission.requestInstallPackages.status;
      if (st.isGranted) return true;
      st = await Permission.requestInstallPackages.request();
      return st.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 下载 APK 并触发安装，返回下载进度回调。
  /// 抛出异常时由 UI 给出"手动安装"指引。
  Future<void> downloadAndInstall(
    String apkUrl, {
    void Function(int percent)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final Uri uri;
    try {
      uri = Uri.parse(apkUrl);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('服务器返回 HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength > 0 ? resp.contentLength : 1;
      final dir = await getExternalStorageDirectory() ??
          await getTemporaryDirectory();
      final file = File('${dir.path}/rev-update.apk');
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in resp.timeout(const Duration(minutes: 3))) {
        got += chunk.length;
        sink.add(chunk);
        if (onProgress != null) {
          onProgress(((got / total) * 100).clamp(0, 100).toInt());
        }
      }
      await sink.flush();
      await sink.close();
      client.close();
      final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        throw Exception('无法调起安装界面：${r.message}');
      }
    } catch (e) {
      client.close();
      rethrow;
    }
  }

  double? _round(dynamic v, [int n = 1]) {
    if (v == null) return null;
    if (v is double && v.isNaN) return null;
    final d = (v as num).toDouble();
    final k = _pow10(n);
    return (d * k).roundToDouble() / k;
  }

  static int _pow10(int n) {
    var k = 1;
    for (var i = 0; i < n; i++) {
      k *= 10;
    }
    return k;
  }
}
