import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:obd_dashboard/services/obd_transport.dart';

/// BLE 串口通道（Nordic UART Service / NUS），实现 [ObdTransport]。
///
/// 与 USB 有线通道共用 [LineFramer] 组帧、共用 [ObdService] 的 ELM 初始化 /
/// PID 轮询 / 解析逻辑。设备在 [BleUartChannel.forDevice] 时注入，connect()
/// 不再写死任何 BluetoothDevice。
class BleUartChannel implements ObdTransport {
  BleUartChannel({BluetoothDevice? device}) : _device = device {
    _lineController = StreamController<String>.broadcast();
    _discController = StreamController<void>.broadcast();
    _framer = LineFramer(onLine: (line) => _lineController.add(line));
  }

  /// 工厂：绑定目标 BLE 设备后即可交给 ObdService.connect()。
  factory BleUartChannel.forDevice(BluetoothDevice device) =>
      BleUartChannel(device: device);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _tx; // 写
  BluetoothCharacteristic? _rx; // 通知
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _connected = false;

  late final LineFramer _framer;
  late final StreamController<String> _lineController;
  late final StreamController<void> _discController;

  @override
  String get displayName {
    final n = _device?.platformName ?? '';
    return n.isEmpty ? 'BLE ELM327' : 'BLE $n';
  }

  @override
  String? get storageId => _device?.remoteId.str;

  @override
  String? get storageLabel =>
      (_device?.platformName ?? '').isEmpty ? null : _device!.platformName;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get onLine => _lineController.stream;

  @override
  Stream<void> get onDisconnected => _discController.stream;

  /// 绑定 / 切换目标设备（重连前可更新）。
  void setDevice(BluetoothDevice device) => _device = device;

  @override
  Future<bool> connect() async {
    final device = _device;
    if (device == null) return false;
    try {
      await device.connect(timeout: const Duration(seconds: 12));
      final services = await device.discoverServices();
      BluetoothCharacteristic? tx;
      BluetoothCharacteristic? rx;
      for (final s in services) {
        // Nordic UART Service：uuid 以 6e400001 开头
        if (s.uuid.str.toLowerCase().startsWith('6e400001')) {
          for (final c in s.characteristics) {
            if (c.uuid.str.toLowerCase().startsWith('6e4000')) {
              if (c.properties.write || c.properties.writeWithoutResponse) {
                tx = c;
              }
              if (c.properties.notify) rx = c;
            }
          }
        }
      }
      if (tx == null || rx == null) {
        throw Exception('未找到 NUS 特征');
      }
      _tx = tx;
      _rx = rx;
      await rx.setNotifyValue(true);
      _framer.reset();
      _notifySub = rx.lastValueStream.listen((v) => _framer.addBytes(v));
      // 监听底层连接态：意外掉线才往上抛（用户主动 disconnect 不抛）。
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _connected) {
          _connected = false;
          _discController.add(null);
        }
      });
      _connected = true;
      return true;
    } catch (e) {
      debugPrint('BLE connect failed: $e');
      await disconnect();
      return false;
    }
  }

  @override
  Future<void> writeString(String s) async {
    if (_tx == null) return;
    final bytes = Uint8List.fromList('$s\r'.codeUnits);
    try {
      if (_tx!.properties.writeWithoutResponse) {
        await _tx!.write(bytes, withoutResponse: true);
      } else {
        await _tx!.write(bytes);
      }
    } catch (e) {
      debugPrint('BLE write failed: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false; // 用户主动断开：抑制后续底层 state 回调里的意外掉线事件
    try {
      await _rx?.setNotifyValue(false);
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _notifySub?.cancel();
    _connSub?.cancel();
    _notifySub = null;
    _connSub = null;
    _tx = null;
    _rx = null;
    _framer.reset();
  }

  @override
  void dispose() {
    disconnect();
    _lineController.close();
    _discController.close();
  }
}
