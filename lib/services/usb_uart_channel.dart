import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:obd_dashboard/services/obd_transport.dart';

/// 已识别的 OBD 串口桥接芯片 VID。
class UsbChip {
  const UsbChip(this.vid, this.name);
  final int vid;
  final String name;

  static const ch340 = UsbChip(0x1A86, 'CH340');
  static const cp210x = UsbChip(0x10C4, 'CP210x');
  static const pl2303 = UsbChip(0x067B, 'PL2303');
  static const ftdi = UsbChip(0x0403, 'FTDI');

  static const known = [ch340, cp210x, pl2303, ftdi];

  static UsbChip? byVid(int? vid) {
    if (vid == null) return null;
    for (final c in known) {
      if (c.vid == vid) return c;
    }
    return null;
  }
}

/// 一条可显示的 USB 串口设备（供连接页列表展示）。
class UsbObdDevice {
  const UsbObdDevice({required this.device, required this.chipName});
  final UsbDevice device;
  final String chipName;

  int? get vid => device.vid;
  int? get pid => device.pid;
  String get vidPid =>
      '${(vid ?? 0).toRadixString(16).padLeft(4, '0').toUpperCase()}:'
      '${(pid ?? 0).toRadixString(16).padLeft(4, '0').toUpperCase()}';

  String get label {
    final p = device.productName;
    return (p == null || p.isEmpty) ? chipName : '$chipName · $p';
  }
}

/// USB 有线串口通道（OTG 转接头插 ELM327），实现 [ObdTransport]。
///
/// 与 BLE 通道共用 [LineFramer] 组帧与 ObdService 的解析逻辑。
/// 支持 CH340 / CP210x / PL2303 / FTDI / CDC ACM；
/// create() 由 usb_serial 库自动弹出 USB 权限请求。
class UsbUartChannel implements ObdTransport {
  UsbUartChannel({required this.device, this.baudRate = 38400}) {
    _lineController = StreamController<String>.broadcast();
    _discController = StreamController<void>.broadcast();
    _framer = LineFramer(onLine: (line) => _lineController.add(line));
  }

  factory UsbUartChannel.forDevice(UsbDevice device, {int baudRate = 38400}) =>
      UsbUartChannel(device: device, baudRate: baudRate);

  final UsbDevice device;
  int baudRate;

  UsbPort? _port;
  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<UsbEvent>? _usbEventSub;
  bool _connected = false;

  late final LineFramer _framer;
  late final StreamController<String> _lineController;
  late final StreamController<void> _discController;

  /// 列出当前插入、可作为 OBD 串口的设备（识别常见桥接芯片；CDC 通用设备也列出）。
  static Future<List<UsbObdDevice>> listObdDevices() async {
    final List<UsbDevice> devices;
    try {
      devices = await UsbSerial.listDevices();
    } catch (e) {
      debugPrint('usb listDevices failed: $e');
      return [];
    }
    final out = <UsbObdDevice>[];
    for (final d in devices) {
      final chip = UsbChip.byVid(d.vid);
      out.add(UsbObdDevice(
        device: d,
        chipName: chip?.name ?? 'CDC/通用(${d.vidPidShort})',
      ));
    }
    // 已知芯片排前面
    out.sort((a, b) => (UsbChip.byVid(b.vid) == null ? 0 : 1)
        .compareTo(UsbChip.byVid(a.vid) == null ? 0 : 1));
    return out;
  }

  @override
  String get displayName => 'USB ${UsbChip.byVid(device.vid)?.name ?? 'CDC'} '
      '(${device.vidPidShort})';

  @override
  String? get storageId => 'USB:${device.vidPidShort}';

  @override
  String? get storageLabel =>
      '${UsbChip.byVid(device.vid)?.name ?? 'CDC'} (${device.vidPidShort})';

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get onLine => _lineController.stream;

  @override
  Stream<void> get onDisconnected => _discController.stream;

  @override
  Future<bool> connect() async {
    try {
      // create() 内部会请求 USB 权限；用户拒绝时返回 null / 抛错。
      final port = await device.create();
      if (port == null) return false;
      final opened = await port.open();
      if (!opened) {
        await port.close();
        return false;
      }
      _port = port;
      await port.setPortParameters(
          baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      // 多数 ELM327 USB  clones 需要 DTR/RTS 才上电输出。
      try {
        await port.setDTR(true);
        await port.setRTS(true);
      } catch (_) {}
      _framer.reset();
      _dataSub = port.inputStream?.listen(
        (data) => _framer.addBytes(data),
        onError: (e) {
          debugPrint('usb input error: $e');
        },
        onDone: _onPhysicalDrop,
      );
      // 监听插拔：拔出时通知上层安全重连 / 提示。
      _usbEventSub = UsbSerial.usbEventStream?.listen((evt) {
        if (evt.event == UsbEvent.ACTION_USB_DETACHED && _connected) {
          final detached = evt.device;
          if (detached?.vid == device.vid && detached?.pid == device.pid) {
            _onPhysicalDrop();
          }
        }
      });
      _connected = true;
      return true;
    } catch (e) {
      debugPrint('USB connect failed: $e');
      await disconnect();
      return false;
    }
  }

  void _onPhysicalDrop() {
    if (!_connected) return;
    _connected = false;
    _discController.add(null);
  }

  @override
  Future<void> writeString(String s) async {
    final port = _port;
    if (port == null) return;
    try {
      await port.write(Uint8List.fromList('$s\r'.codeUnits));
    } catch (e) {
      debugPrint('USB write failed: $e');
    }
  }

  /// 切换波特率（9600 / 38400 / 115200 兜底时用）。
  Future<void> setBaudRate(int baud) async {
    baudRate = baud;
    final port = _port;
    if (port == null) return;
    try {
      await port.setPortParameters(
          baud, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
    } catch (_) {}
  }

  @override
  Future<void> disconnect() async {
    _connected = false; // 抑制插拔回调里的意外掉线事件
    await _dataSub?.cancel();
    await _usbEventSub?.cancel();
    _dataSub = null;
    _usbEventSub = null;
    try {
      await _port?.close();
    } catch (_) {}
    _port = null;
    _framer.reset();
  }

  @override
  void dispose() {
    disconnect();
    _lineController.close();
    _discController.close();
  }
}

/// 给 UsbDevice 补一个紧凑 VID:PID 展示扩展（避免在文件里到处拼）。
extension on UsbDevice {
  String get vidPidShort =>
      '${(vid ?? 0).toRadixString(16).padLeft(4, '0').toUpperCase()}:'
      '${(pid ?? 0).toRadixString(16).padLeft(4, '0').toUpperCase()}';
}
