import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/services/ble_uart_channel.dart';
import 'package:obd_dashboard/services/obd_service.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';
import 'package:obd_dashboard/services/usb_uart_channel.dart';
import 'package:obd_dashboard/services/wifi_obd_channel.dart';

/// 上车自动连接：冷启动 / 回到前台时，按上次成功连接的设备直接重连。
///
/// 早先只有"进入连接页"才会自动连，车机开机自启后停在仪表盘，等于每次都要
/// 手动进一次连接页——这是 Torque 之类老牌应用被吐槽最多的点，这里补上。
///
/// 三条纪律：
///  - 只在实车模式、未连接、且用户没有手动断开过时尝试；
///  - 8 秒内不重复尝试（避免前后台切换时猛连）；
///  - USB 设备按 VID:PID 匹配，BLE 按 remoteId 直接建句柄（无需重新扫描）。
class AutoConnect {
  AutoConnect._();

  static DateTime _lastTry = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _busy = false;

  /// 用户手动断开后置 true，本次进程内不再自动重连；手动连接成功即复位。
  static bool userOptOut = false;

  static Future<bool> tryKnown({
    required ObdService obd,
    required TelemetryService tele,
    bool force = false,
  }) async {
    if (obd.isConnected) return true;
    if (userOptOut && !force) return false;
    if (tele.dataMode != 'real') return false;
    if (_busy) return false;
    final now = DateTime.now();
    if (!force && now.difference(_lastTry).inSeconds < 8) return false;
    _lastTry = now;

    final id = await AppStore.instance.getKnownDeviceId();
    if (id == null || id.isEmpty) return false;

    _busy = true;
    try {
      if (id.toUpperCase().startsWith('USB:')) {
        final list = await UsbUartChannel.listObdDevices();
        UsbObdDevice? hit;
        for (final d in list) {
          if ('USB:${d.vidPid}'.toUpperCase() == id.toUpperCase()) {
            hit = d;
            break;
          }
        }
        if (hit == null) return false;
        debugPrint('AutoConnect: USB ${hit.label}');
        return await obd.connect(UsbUartChannel.forDevice(hit.device));
      }
      if (id.startsWith('WiFi:')) {
        // WiFi 盒子地址固定（192.168.0.10/.123:35000），通道内部会依次尝试。
        debugPrint('AutoConnect: WiFi（按默认端点重试）');
        return await obd.connect(WifiObdChannel());
      }
      final dev = BluetoothDevice.fromId(id);
      debugPrint('AutoConnect: BLE $id');
      return await obd.connect(BleUartChannel.forDevice(dev));
    } catch (e) {
      debugPrint('AutoConnect 失败：$e');
      return false;
    } finally {
      _busy = false;
    }
  }
}
