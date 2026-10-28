import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:obd_dashboard/core/game/game_telemetry.dart';
import 'package:obd_dashboard/core/game/game_udp_parser.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';

/// 游戏 UDP 遥测监听服务：绑定本机端口，接收游戏 Data Out 广播，
/// 解析后推入 [TelemetryService.onGameFrame]。
///
/// 同一时刻只监听一个端口（一个游戏）。切换游戏即重启监听。
class GameUdpService {
  GameUdpService({TelemetryService? telemetry})
      : _telemetry = telemetry;

  final TelemetryService? _telemetry;

  RawDatagramSocket? _socket;
  GameProtocol? _protocol;
  int _packets = 0;
  int get packets => _packets;
  GameProtocol? get protocol => _protocol;
  bool get isRunning => _socket != null;

  /// 启动监听 [protocol] 对应的端口。失败抛异常由 UI 提示。
  Future<void> start(GameProtocol protocol) async {
    await stop();
    _protocol = protocol;
    // 监听 0.0.0.0 的指定端口；游戏向手机/车机 IP 发送广播或单播。
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      protocol.port,
      reuseAddress: true,
    );
    _socket = socket;
    _packets = 0;
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      final data = Uint8List.fromList(dg.data);
      final t = GameUdpParser.parse(protocol, data);
      if (t != null && t.isUsable) {
        _packets++;
        try {
          _telemetry?.onGameFrame(t);
        } catch (e) {
          debugPrint('game frame feed failed: $e');
        }
      }
    }, onError: (e) {
      debugPrint('game udp error: $e');
      stop();
    });
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _protocol = null;
    _telemetry?.stopGameSource();
  }
}
