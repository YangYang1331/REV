import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// 扫描逻辑（参考原版 features/connection/scan_logic.dart）。
/// 负责请求权限 + BLE 扫描，优先展示像 OBD/ELM 的设备。
class ScanLogic {
  static bool _scanning = false;
  static final List<BluetoothDevice> _results = [];
  static bool get scanning => _scanning;

  /// 最近一次扫描发现的设备（连接自检页读取数量与候选设备）。
  static List<BluetoothDevice> get lastResults => List.unmodifiable(_results);

  static Future<bool> ensurePermissions() async {
    final status = await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    if (status == PermissionStatus.denied && !await Permission.location.isGranted) {
      await Permission.location.request();
    }
    return status.isGranted;
  }

  /// 启动扫描，返回增量结果列表。
  /// [onFound] 每发现一台设备回调一次。
  static Future<void> startScan(void Function(List<BluetoothDevice>) onFound) async {
    if (_scanning) return;
    if (!await ensurePermissions()) return;
    _scanning = true;
    _results.clear();
    onFound(List.unmodifiable(_results));

    // 每发现设备就刷新一次列表
    FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (!_results.any((d) => d.remoteId == r.device.remoteId)) {
          _results.add(r.device);
        }
      }
      onFound(List.unmodifiable(_results));
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    _scanning = false;
  }

  static Future<void> stopScan() async {
    if (!_scanning) return;
    await FlutterBluePlus.stopScan();
    _scanning = false;
  }
}
