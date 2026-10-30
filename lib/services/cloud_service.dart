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
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/models/obd_data.dart';
import 'package:obd_dashboard/services/gps_fix.dart';

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
  // 3 秒一帧 → 1200 帧 ≈ 1 小时断网；单帧 ~300B，prefs 里约 400KB。
  static const _maxQueue = 1200;

  String _endpoint = defaultEndpoint;
  String get endpoint => _endpoint;
  String get baseUrl => _endpoint.replaceAll(RegExp(r'/api/v1.*$'), '');

  /// 404 自愈只尝试一次，避免坏地址每帧都双发。
  bool _healTried = false;
  bool _healed = false;
  int _lastStatusCode = 0;

  /// 未配置服务器地址：设置页提示用户填写自己部署的地址。
  bool get needsUserServer => _endpoint.trim().isEmpty;

  String _deviceId = 'unknown';
  String get deviceId => _deviceId;

  // ---- 隐私授权（默认：GPS 不上传、车辆数据上传）----
  bool _gpsUpload = AppStore.gpsUpload;
  bool _cloudUpload = AppStore.cloudUpload;
  bool get gpsUpload => _gpsUpload;
  bool get cloudUpload => _cloudUpload;

  /// GPS 轨迹属于敏感个人信息，必须用户单独同意后才随帧上传。
  Future<void> setGpsUpload(bool v) async {
    _gpsUpload = v;
    await AppStore.instance.setGpsUpload(v);
    if (!v) _stopGps();
  }

  /// 关闭后完全不上报（"仅本地使用"），离线队列也停止补传。
  Future<void> setCloudUpload(bool v) async {
    _cloudUpload = v;
    await AppStore.instance.setCloudUpload(v);
  }

  /// 上报地址是否走公网明文 HTTP（域名强制 HTTPS，只有公网 IP 才会落到这里）。
  bool get isPlaintextPublic {
    final u = Uri.tryParse(_endpoint);
    if (u == null || u.host.isEmpty) return false;
    return u.scheme.toLowerCase() == 'http' && !isPrivateHost(u.host);
  }

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
        ? normalizeEndpoint(saved)
        : defaultEndpoint;
    // 旧版本可能存了带多余路径的地址，规范化后写回，避免每次启动都 404。
    if (saved != null && saved.isNotEmpty && _endpoint != saved.trim()) {
      await prefs.setString(_kEndpoint, _endpoint);
    }

    var did = prefs.getString(_kDeviceId);
    if (did == null || did.isEmpty) {
      did = 'rev-${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
      await prefs.setString(_kDeviceId, did);
    }
    _deviceId = did;

    // 隐私授权（默认：位置不上传、车辆数据上报）
    _gpsUpload = await AppStore.instance.getGpsUpload();
    _cloudUpload = await AppStore.instance.getCloudUpload();
  }

  Future<void> setEndpoint(String v) async {
    _endpoint = normalizeEndpoint(v);
    _healTried = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEndpoint, _endpoint);
  }

  /// 规范化上报地址：补协议、去尾斜杠、补 `/api/v1/report`。
  ///
  /// 用户常把地址写成 `http://host/c`、`139.224.30.235` 这类形式，直接拼上去
  /// 就是 404（看板永远空白）。这里统一收敛成 `scheme://host[:port]/api/v1/report`；
  /// 已带 `/api/v1/xxx` 的保持原样，自建反代的子路径前缀不会被吃掉。
  ///
  /// 协议强制：域名一律升级为 HTTPS（token 与行车轨迹不能明文跑公网）；
  /// 只有 localhost / 内网段 / `.local` 保留 HTTP。公网裸 IP 保留 HTTP 但会在
  /// 设置页标注"明文"，因为它通常没有匹配 IP 的证书，强升会让上报直接失败。
  static String normalizeEndpoint(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    final hasScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(s);
    if (!hasScheme) {
      final host = _hostOf(s);
      // 裸域名优先走 HTTPS；裸 IP / 内网主机保持 HTTP（多为自建无证书）。
      s = (_isIpv4(host) || isPrivateHost(host) ? 'http://' : 'https://') + s;
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    final u = Uri.tryParse(s);
    if (u != null && u.host.isNotEmpty) {
      final isHttp = u.scheme.toLowerCase() == 'http';
      if (isHttp && !isPrivateHost(u.host) && !_isIpv4(u.host)) {
        s = 'https://${s.substring(s.indexOf('://') + 3)}';
      }
    }
    if (RegExp(r'/api/v1/', caseSensitive: false).hasMatch(s)) return s;
    return '$s/api/v1/report';
  }

  /// 取出待规范化字符串里的主机名（容忍 `host:port/path`）。
  static String _hostOf(String s) {
    final noScheme = s.contains('://') ? s.split('://').last : s;
    return noScheme.split(RegExp(r'[/?#]')).first.split(':').first;
  }

  static bool _isIpv4(String host) =>
      RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host);

  /// 内网 / 本机地址：这些允许明文 HTTP（自建家庭服务器、本机调试）。
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty) return false;
    if (h == 'localhost' ||
        h == '::1' ||
        h.endsWith('.local') ||
        h.endsWith('.lan') ||
        h.endsWith('.internal')) {
      return true;
    }
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
    if (m == null) return false;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    if (a == 127 || a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true;
    return false;
  }

  /// 同一台服务器上的规范上报地址（用于 404 自愈）；已规范则返回 null。
  static String? canonicalReportUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return null;
    final canon = '${u.scheme}://${u.authority}/api/v1/report';
    return canon == url ? null : canon;
  }

  // ── GPS ──
  /// 懒启动：只在真正需要上报时才开启，未登录/未连车时不后台定位。
  /// 失败后 10 分钟内不再重试，避免每隔 3 秒弹一次权限框。
  Future<bool> startGps() async {
    if (!_gpsUpload) return false; // 未授权位置上传 → 根本不开定位
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
      ).listen((p) {
        _loc = p;
        // 行程记录复用同一份定位（不额外开流）；隐私未授权时这条流根本不会启动。
        GpsFixBus.last = GpsFix(
          lat: p.latitude,
          lng: p.longitude,
          speedKmh:
              (p.speed.isFinite ? p.speed * 3.6 : 0.0).clamp(0.0, 400.0),
        );
      }, onError: (_) {});
      _gpsStarted = true;
      return true;
    } finally {
      _gpsRequesting = false;
    }
  }

  /// 关闭位置上传时立即停止定位并丢弃缓存坐标。
  void _stopGps() {
    _posSub?.cancel();
    _posSub = null;
    _gpsStarted = false;
    _loc = null;
    GpsFixBus.clear();
  }

  /// 上报一帧（实车/演示/游戏都上报；看板用 source 区分）。
  /// [token] 登录态：有则带 `Authorization: Bearer <token>`。
  /// 网络失败（非 401）帧进离线队列待补传；401 直接丢弃（清登录态由上层处理）。
  Future<void> report(ObdData d, {String? token}) async {
    if (!_cloudUpload) return; // "仅本地使用"：完全不上报
    final url = _endpoint.trim();
    if (url.isEmpty) return;
    // 只在真正上报时开启 GPS：未登录 / 未连车时不后台定位耗电。
    if (_gpsUpload && !_gpsStarted) unawaited(startGps());
    final map = _buildFrame(d);
    var r = await _postFrame(url, map, token);
    // 404 自愈：地址多写了路径（如 /c/api/v1/report）时，改投同主机的规范地址。
    // 成功一次就把修正后的地址落盘，用户不用去设置里手改。
    if (r == false && _lastStatusCode == 404 && !_healTried) {
      final alt = canonicalReportUrl(url);
      if (alt != null) {
        _healTried = true;
        final r2 = await _postFrame(alt, map, token);
        if (r2 == true) {
          await setEndpoint(alt);
          _healed = true;
          debugPrint('cloud endpoint 自愈：$url → $alt');
          r = true;
        } else if (r2 == null) {
          // 401 说明地址对了，只是还没登录：同样落盘。
          await setEndpoint(alt);
          _healed = true;
          r = null;
        }
      }
    }
    if (r == true) {
      await _maybeFlush(token);
    } else if (r == false) {
      await _enqueue(map);
    }
    // r == null 表示 401，不排队。
  }

  /// 是否发生过地址自愈（设置页可提示“已自动修正”）。
  bool get endpointHealed => _healed;

  /// 恢复为构建时注入的默认地址（开源版可能为空 = 不上报）。
  Future<void> resetEndpoint() async {
    _endpoint = defaultEndpoint;
    _healTried = false;
    _healed = false;
    final prefs = await SharedPreferences.getInstance();
    if (defaultEndpoint.isEmpty) {
      await prefs.remove(_kEndpoint);
    } else {
      await prefs.setString(_kEndpoint, defaultEndpoint);
    }
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
    if (_gpsUpload && _loc != null) {
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
      _lastStatusCode = code;
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
        _noteError(code == 404
            ? 'HTTP 404：上报地址应为 …/api/v1/report'
            : '服务器返回 HTTP $code');
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
  ///
  /// 优先走 `/api/v1/report/batch`（100 帧/请求），老服务器没有该路由时
  /// 自动退回逐帧上报。任何失败都保留剩余帧，等下一轮。
  Future<void> flushQueue({String? token, int maxFrames = 300}) async {
    if (!_cloudUpload) return;
    if (token == null || token.isEmpty) return;
    final url = _endpoint.trim();
    if (url.isEmpty) return;
    var q = await _readQueue();
    if (q.isEmpty) return;

    var sent = 0;
    var batchOk = true;
    while (q.isNotEmpty && sent < maxFrames) {
      final size = (maxFrames - sent).clamp(1, 100);
      final chunk = q.take(size).toList();
      final n = await _postBatch(_batchUrl, chunk, token);
      if (n == _batchUnsupported) {
        batchOk = false;
        break;
      }
      if (n < 0) {
        await _writeQueue(q);
        debugPrint('offline queue: batch 失败，保留 ${q.length} 帧');
        return;
      }
      q = q.sublist(n > chunk.length ? chunk.length : n);
      sent += n;
      if (n < chunk.length) break;
    }

    if (!batchOk) {
      // 逐帧兜底（旧服务器）
      final remaining = <dynamic>[];
      var i = 0;
      while (i < q.length && sent < maxFrames) {
        final item = q[i];
        if (item is! Map<String, dynamic>) {
          i++;
          continue;
        }
        final r = await _postFrame(url, item, token);
        if (r != true) break; // 401 / 网络错误：本轮停止
        i++;
        sent++;
      }
      remaining.addAll(q.sublist(i));
      q = remaining;
    }

    await _writeQueue(q);
    if (sent > 0) debugPrint('offline queue flushed: $sent sent, ${q.length} left');
  }

  static const int _batchUnsupported = -2;

  /// 批量上报地址：`.../api/v1/report` → `.../api/v1/report/batch`。
  String get _batchUrl =>
      _endpoint.replaceFirst(RegExp(r'/report$'), '/report/batch');

  /// 返回：>=0 服务器接受的帧数；-1 可重试失败；[_batchUnsupported] 路由不存在。
  Future<int> _postBatch(String url, List<dynamic> frames, String? token) async {
    if (url.isEmpty || frames.isEmpty) return _batchUnsupported;
    try {
      final req = await _client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      req.write(jsonEncode({'frames': frames}));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final code = resp.statusCode;
      _lastStatusCode = code;
      final body = await resp.transform(utf8.decoder).join();
      if (code == 404 || code == 405) return _batchUnsupported;
      if (code == 401) {
        _lastUnauthorized = true;
        _lastError = '登录已过期，请重新登录';
        try {
          onUnauthorized?.call();
        } catch (_) {}
        return -1;
      }
      if (code < 200 || code >= 300) {
        _noteError('批量上报 HTTP $code');
        return -1;
      }
      _noteOk();
      final j = jsonDecode(body.isEmpty ? '{}' : body);
      final n = (j is Map ? j['accepted'] : null);
      return n is num ? n.toInt().clamp(0, frames.length) : frames.length;
    } catch (e) {
      _http?.close(force: true);
      _http = null;
      _noteError('网络不可达：$e');
      return -1;
    }
  }

  /// 当前离线待补传帧数（供 UI 展示）。
  Future<int> pendingCount() async => (await _readQueue()).length;

  // ── 应用内更新 ──
  /// 拉取本车最近 N 小时的历史趋势（服务端分钟级聚合）。
  /// 返回 `{points:[{t,ct,ot,volt,spd}], stepMin:n}`；未登录/无权限/失败返回 null。
  Future<Map<String, dynamic>?> fetchHistory({
    required String deviceId,
    int hours = 24,
    String? token,
  }) async {
    if (_endpoint.trim().isEmpty || token == null || token.isEmpty) return null;
    final base = baseUrl;
    final uri = Uri.parse('$base/api/v1/history').replace(queryParameters: {
      'deviceId': deviceId,
      'hours': '$hours',
    });
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(uri);
      req.headers.set('Authorization', 'Bearer $token');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) {
        debugPrint('history HTTP ${resp.statusCode}');
        return null;
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('history failed: $e');
      return null;
    }
  }

  /// 返回 null 表示确已是最新；否则返回 {versionCode,versionName,notes,apkUrl,...}。
  /// baseUrl 同时支持 https 域名与 IP:端口。
  ///
  /// 注意：网络/服务器异常一律抛出，不能返回 null —— 否则界面会把"连不上"
  /// 误报成"已是最新版本"，用户会卡在旧版本里（v2.16.x 的真实故障）。
  Future<Map<String, dynamic>?> checkUpdate(int currentCode) async {
    if (_endpoint.trim().isEmpty) {
      throw StateError('未配置更新服务器地址');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/v1/latest'));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw HttpException('服务器返回 HTTP ${resp.statusCode}', uri: req.uri);
      }
      final rel = jsonDecode(body) as Map<String, dynamic>;
      final code = (rel['versionCode'] as num?)?.toInt() ?? 0;
      if (code <= 0) {
        throw const FormatException('更新信息缺少 versionCode');
      }
      if (code <= currentCode) return null;
      return rel;
    } finally {
      client.close();
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
