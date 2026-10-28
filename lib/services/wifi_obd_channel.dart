import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:obd_dashboard/services/obd_transport.dart';

/// WiFi ELM327 适配器常见默认端点。
///
/// 市面上廉价 WiFi OBD 盒子出厂 AP：手机连盒子热点（或同一路由器）后，
/// 盒子监听 TCP 35000。最常见 IP 是 192.168.0.10 / 192.168.0.123。
/// 这里做成可配置列表，connect 时逐个尝试，第一个握手成功即采用。
class WifiObdEndpoint {
  const WifiObdEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  /// 出厂默认尝试列表（按命中率从高到低）。
  static const List<WifiObdEndpoint> defaults = [
    WifiObdEndpoint(host: '192.168.0.10', port: 35000),
    WifiObdEndpoint(host: '192.168.0.123', port: 35000),
    WifiObdEndpoint(host: '192.168.0.1', port: 35000),
    WifiObdEndpoint(host: '192.168.100.236', port: 35000),
  ];

  @override
  String toString() => '$host:$port';
}

/// WiFi/TCP OBD 传输通道，实现 [ObdTransport]。
///
/// 与 BLE/USB 共用 [LineFramer] 组帧与 ObdService 的解析。
/// connect() 按 [WifiObdEndpoint.defaults] 逐个尝试 TCP 连接，
/// 任何一个 connect 成功即采用；物理断网（Socket 对端关闭）触发
/// [onDisconnected]，由上层指数退避重连。
class WifiObdChannel implements ObdTransport {
  WifiObdChannel({
    this.endpoints = WifiObdEndpoint.defaults,
    this.connectTimeout = const Duration(seconds: 3),
  }) {
    _lineController = StreamController<String>.broadcast();
    _discController = StreamController<void>.broadcast();
    _framer = LineFramer(onLine: (line) => _lineController.add(line));
  }

  /// 指定单个端点（连接页高级选项用）。
  factory WifiObdChannel.single(String host, int port) =>
      WifiObdChannel(endpoints: [WifiObdEndpoint(host: host, port: port)]);

  final List<WifiObdEndpoint> endpoints;
  final Duration connectTimeout;

  Socket? _socket;
  StreamSubscription<List<int>>? _socketSub;
  bool _connected = false;
  WifiObdEndpoint? _active;

  late final LineFramer _framer;
  late final StreamController<String> _lineController;
  late final StreamController<void> _discController;

  @override
  String get displayName {
    final e = _active;
    return e == null ? 'WiFi OBD' : 'WiFi OBD ($e)';
  }

  @override
  String? get storageId => _active == null
      ? 'WiFi:default'
      : 'WiFi:${_active!.host}:${_active!.port}';

  @override
  String? get storageLabel => _active == null
      ? 'WiFi OBD'
      : 'WiFi OBD (${_active!.host})';

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get onLine => _lineController.stream;

  @override
  Stream<void> get onDisconnected => _discController.stream;

  @override
  Future<bool> connect() async {
    Socket? socket;
    WifiObdEndpoint? chosen;
    SocketException? lastErr;
    for (final e in endpoints) {
      try {
        socket = await Socket.connect(
          e.host,
          e.port,
          timeout: connectTimeout,
        );
        chosen = e;
        break;
      } catch (err) {
        lastErr = err is SocketException ? err : SocketException(err.toString());
        debugPrint('WiFi OBD 连接 $e 失败: $err');
      }
    }
    if (socket == null || chosen == null) {
      debugPrint('WiFi OBD 全部端点连接失败: $lastErr');
      return false;
    }
    _socket = socket;
    _active = chosen;
    // WiFi 盒子链路延迟略高，不设 keepalive 也行；这里打开 TCP keepalive
    // 让手机切后台/锁屏时死链尽快被发现。
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _framer.reset();
    _socketSub = socket.listen(
      (data) => _framer.addBytes(data),
      onError: (e) {
        debugPrint('WiFi OBD socket error: $e');
        _onPhysicalDrop();
      },
      onDone: _onPhysicalDrop,
    );
    _connected = true;
    return true;
  }

  void _onPhysicalDrop() {
    if (!_connected) return;
    _connected = false;
    _discController.add(null);
  }

  @override
  Future<void> writeString(String s) async {
    final sock = _socket;
    if (sock == null) return;
    try {
      sock.add('$s\r'.codeUnits);
      await sock.flush();
    } catch (e) {
      debugPrint('WiFi OBD write failed: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _framer.reset();
  }

  @override
  void dispose() {
    disconnect();
    _lineController.close();
    _discController.close();
  }
}
