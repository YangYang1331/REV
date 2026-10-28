import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/auth/auth_screen.dart';
import 'package:obd_dashboard/features/connection/preheat_screen.dart';
import 'package:obd_dashboard/features/connection/scan_logic.dart';
import 'package:obd_dashboard/features/connection/self_check_screen.dart';
import 'package:obd_dashboard/features/dashboard/widgets/data_mode_selector.dart';
import 'package:obd_dashboard/services/ble_uart_channel.dart';
import 'package:obd_dashboard/services/usb_uart_channel.dart';
import 'package:obd_dashboard/services/wifi_obd_channel.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  List<BluetoothDevice> _devices = [];
  bool _scanning = false;
  String? _connectingId;
  String _status = '';

  // 数据源：蓝牙 BLE 或 USB 有线
  String _dataSource = 'ble'; // 'ble' | 'usb'

  // USB 设备列表
  List<UsbObdDevice> _usbDevices = [];
  String? _usbConnectingId;
  StreamSubscription<UsbEvent>? _usbEventSub;

  // 已记忆设备（短板1：进入页面自动连接）
  String? _knownId;
  String? _knownName;
  bool _autoConnecting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _startUsbEventListen();
  }

  @override
  void dispose() {
    _usbEventSub?.cancel();
    super.dispose();
  }

  /// 监听 USB 插拔：插入自动刷新列表，拔出则提示并回流状态。
  void _startUsbEventListen() {
    _usbEventSub = UsbSerial.usbEventStream?.listen((evt) async {
      if (!mounted) return;
      if (evt.event == UsbEvent.ACTION_USB_ATTACHED) {
        await _listUsbDevices();
      } else if (evt.event == UsbEvent.ACTION_USB_DETACHED) {
        setState(() => _status = 'USB 设备已拔出');
        await _listUsbDevices();
      }
    });
  }

  Future<void> _listUsbDevices() async {
    try {
      final list = await UsbUartChannel.listObdDevices();
      if (!mounted) return;
      setState(() => _usbDevices = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '枚举 USB 设备失败：$e');
    }
  }

  Future<void> _bootstrap() async {
    final knownId = await AppStore.instance.getKnownDeviceId();
    if (!mounted) return;
    if (knownId == null || knownId.isEmpty) return;
    final knownName = await AppStore.instance.getKnownDeviceName();
    setState(() {
      _knownId = knownId;
      _knownName = knownName;
    });
    final tele = ref.read(telemetryProvider);
    final obd = ref.read(obdServiceProvider);
    // 仅在实车模式且未连接时自动连已记忆设备；演示模式不打扰
    if (tele.isRealMode && !obd.isConnected) {
      await _autoConnect(knownId, knownName ?? knownId);
    }
  }

  /// 选择器切到"实车 OBD"后回调：有已记忆设备走自动连接，否则直接扫描。
  Future<void> _onEnterReal() async {
    if (!mounted) return;
    final obd = ref.read(obdServiceProvider);
    if (obd.isConnected) return;
    var knownId = _knownId;
    knownId ??= await AppStore.instance.getKnownDeviceId();
    if (!mounted) return;
    if (knownId != null && knownId.isNotEmpty) {
      final name =
          _knownName ?? await AppStore.instance.getKnownDeviceName();
      if (!mounted) return;
      await _autoConnect(knownId, name ?? knownId);
    } else {
      await _startScan();
    }
  }

  /// 选择器切到"USB 有线 OBD"后回调：切到 USB 数据源并枚举设备。
  Future<void> _onEnterUsb() async {
    if (!mounted) return;
    setState(() {
      _dataSource = 'usb';
      _status = '正在枚举 USB 串口设备…';
    });
    await _listUsbDevices();
    if (!mounted) return;
    if (_usbDevices.isEmpty) {
      setState(() => _status =
          '未发现 USB 串口设备：请用 OTG 转接头插入 ELM327（CH340/CP210x/FTDI）');
    } else {
      setState(() => _status = '发现 ${_usbDevices.length} 个串口设备，点选连接');
    }
  }

  /// 选择器切到"WiFi OBD"后回调：直接按默认端点列表尝试 TCP 连接。
  Future<void> _onEnterWifi() async {
    if (!mounted) return;
    final obd = ref.read(obdServiceProvider);
    if (obd.isConnected) return;
    setState(() {
      _dataSource = 'wifi';
      _status = '正在尝试连接 WiFi OBD（192.168.0.10 / 0.123:35000）…';
    });
    bool ok;
    try {
      ok = await obd.connect(WifiObdChannel());
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'WiFi OBD 连接出错：$e');
      return;
    }
    if (!mounted) return;
    if (ok) {
      setState(() => _status = 'WiFi OBD 已连接，数据通道已启动');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi OBD 已连接，返回仪表盘查看实时数据')),
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() => _status =
          'WiFi OBD 连接失败：请确认手机已连盒子热点（或同一路由器）');
    }
  }

  /// 自动扫描并连接已记忆设备。
  Future<void> _autoConnect(String knownId, String knownName) async {
    setState(() => _autoConnecting = true);
    BluetoothDevice? matched;
    await ScanLogic.startScan((list) {
      if (!mounted) return;
      setState(() => _devices = list);
      if (matched != null) return;
      for (final d in list) {
        if (d.remoteId.str == knownId) {
          matched = d;
          break;
        }
      }
      if (matched != null) ScanLogic.stopScan();
    });
    if (!mounted) return;
    if (matched != null) {
      await _connect(matched!);
    } else {
      setState(() {
        _autoConnecting = false;
        _status = '未发现已记忆设备「$knownName」，请确认 ELM327 已上电后手动扫描';
      });
    }
  }

  void _cancelAutoConnect() {
    ScanLogic.stopScan();
    setState(() {
      _autoConnecting = false;
      _status = '已取消自动连接，请手动选择设备';
    });
  }

  Future<void> _forgetKnown() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('忘记已记忆设备？'),
        content: const Text('忘记后下次进入本页将不再自动连接该 OBD 设备。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('忘记')),
        ],
      ),
    );
    if (ok != true) return;
    await AppStore.instance.clearKnownDevice();
    if (!mounted) return;
    setState(() {
      _knownId = null;
      _knownName = null;
    });
  }

  Future<void> _startScan() async {
    setState(() => _scanning = true);
    try {
      await ScanLogic.startScan((list) {
        if (mounted) setState(() => _devices = list);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _status = '扫描失败：$e（请确认蓝牙已开启并授予权限）');
      }
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice d) async {
    final obd = ref.read(obdServiceProvider);
    setState(() {
      _connectingId = d.remoteId.str;
      _status = '正在连接 ${d.platformName.isEmpty ? d.remoteId.str : d.platformName}…';
    });
    bool ok;
    try {
      // 注入 BLE transport（ObdService 不再写死 BluetoothDevice）
      ok = await obd.connect(BleUartChannel.forDevice(d));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectingId = null;
        _autoConnecting = false;
        _status = '连接出错：$e';
      });
      return;
    }
    if (!mounted) return;
    if (ok) {
      setState(() {
        _connectingId = null;
        _autoConnecting = false;
        _status = '已连接，数据通道已启动';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OBD 已连接，返回仪表盘查看实时数据')),
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() {
        _connectingId = null;
        _autoConnecting = false;
        _status = '连接失败，请确认设备是 BLE ELM327 且已上电';
      });
    }
  }

  /// 连接 USB 有线 OBD：枚举 → 点选 → create() 弹权限 → 注入 transport。
  Future<void> _connectUsb(UsbObdDevice d) async {
    final obd = ref.read(obdServiceProvider);
    setState(() {
      _usbConnectingId = d.vidPid;
      _status = '正在连接 ${d.label}（${d.vidPid}）…';
    });
    bool ok;
    try {
      final channel = UsbUartChannel.forDevice(d.device);
      ok = await obd.connect(channel);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _usbConnectingId = null;
        _status = 'USB 连接出错：$e（若弹出权限框请点允许）';
      });
      return;
    }
    if (!mounted) return;
    if (ok) {
      setState(() {
        _usbConnectingId = null;
        _status = 'USB 已连接，数据通道已启动';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('USB OBD 已连接，返回仪表盘查看实时数据')),
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() {
        _usbConnectingId = null;
        _status = 'USB 连接失败：权限被拒 / 设备占用 / 波特率不匹配';
      });
    }
  }

  void _openAuth() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    final obd = ref.watch(obdServiceProvider);
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接车辆'),
        actions: [
          IconButton(
            tooltip: auth.isLoggedIn ? '账号：${auth.username}' : '登录 / 注册',
            icon: Icon(auth.isLoggedIn
                ? Icons.account_circle
                : Icons.account_circle_outlined),
            onPressed: _openAuth,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 账号状态
          Card(
            child: ListTile(
              leading: Icon(
                auth.isLoggedIn ? Icons.verified_user : Icons.login,
                color: auth.isLoggedIn
                    ? const Color(0xFF2EE68A)
                    : const Color(0xFFF2B23B),
              ),
              title: Text(auth.isLoggedIn
                  ? '当前账号：${auth.username ?? '-'}'
                  : '未登录'),
              subtitle: Text(
                auth.isLoggedIn
                    ? (auth.isAdmin
                        ? '管理员 · 可查看全部车辆数据'
                        : '普通用户 · 仅查看自己的车辆')
                    : '登录后车辆数据才会上报到车队看板',
              ),
              trailing: TextButton(
                onPressed: _openAuth,
                child: Text(auth.isLoggedIn ? '账号' : '登录 / 注册'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 数据源模式选择（演示 DEMO / 蓝牙 BLE OBD / USB 有线 OBD）
          DataModeSelector(onEnterReal: _onEnterReal, onEnterUsb: _onEnterUsb, onEnterWifi: _onEnterWifi),
          const SizedBox(height: 8),
          // 实车模式但未连接时的兜底提示：可切回演示
          if (t.isRealMode && !obd.isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x2227D6E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_searching,
                      color: Color(0xFF9BE8F2), size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('实车模式未连接 OBD，等待扫描/连接…',
                        style: TextStyle(
                            color: Color(0xFFBEEBF2), fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => t.selectMode('demo'),
                    child: const Text('先用演示'),
                  ),
                ],
              ),
            ),
          // 自动连接进度条
          if (_autoConnecting)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x22F2B23B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '正在连接已记忆设备「${_knownName ?? _knownId ?? ''}」…',
                      style: const TextStyle(
                          color: Color(0xFFFFE0A8), fontSize: 13),
                    ),
                  ),
                  TextButton(
                      onPressed: _cancelAutoConnect,
                      child: const Text('取消')),
                ],
              ),
            ),
          // 已记忆设备（可忘记）
          if (_knownId != null && !_autoConnecting && !obd.isConnected)
            Card(
              child: ListTile(
                leading: const Icon(Icons.memory, color: Color(0xFF27D6E6)),
                title: Text('已记忆设备：${_knownName ?? _knownId}'),
                subtitle: const Text('下次进入本页将自动连接'),
                trailing: TextButton(
                    onPressed: _forgetKnown, child: const Text('忘记')),
              ),
            ),
          const SizedBox(height: 8),
          // 自检 / 引导入口
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SelfCheckScreen()),
                  ),
                  icon: const Icon(Icons.bug_report, size: 18),
                  label: const Text('连接自检'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PreheatScreen()),
                  ),
                  icon: const Icon(Icons.local_fire_department, size: 18),
                  label: const Text('连接引导'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (obd.isConnected)
            Card(
              color: const Color(0x222EE68A),
              child: ListTile(
                leading: const Icon(Icons.bluetooth_connected,
                    color: Color(0xFF2EE68A)),
                title: const Text('OBD 已连接'),
                subtitle: Text(_status.isEmpty ? '实时数据采集中' : _status),
                trailing: TextButton(
                  // 主动断开：基座已回调 tele.onObdDisconnected，模式保持 real 不回退演示
                  onPressed: () async {
                    try {
                      await obd.disconnect();
                    } catch (_) {}
                    if (mounted) setState(() {});
                  },
                  child: const Text('断开'),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF27D6E6).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'iOS 不支持经典蓝牙 SPP，请使用 BLE 版 ELM327（Nordic UART）或 WiFi 版；Android 经典蓝牙与 BLE 均可用。',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          if (_status.isNotEmpty && !obd.isConnected)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_status,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
            ),
          // 蓝牙 BLE 设备列表
          if (_dataSource == 'ble') ...[
            Row(
              children: [
                const Text('蓝牙设备',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_scanning)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  FilledButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.bluetooth_searching, size: 18),
                    label: const Text('扫描'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text('未发现设备，点"扫描"搜索 ELM327（BLE）',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38)),
              )
            else
              ..._devices.map((d) {
                final isConnecting = _connectingId == d.remoteId.str;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(d.platformName.isEmpty
                        ? d.remoteId.str
                        : d.platformName),
                    subtitle: Text(d.remoteId.str),
                    trailing: isConnecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : null,
                    onTap: isConnecting ? null : () => _connect(d),
                  ),
                );
              }),
          ],
          // USB 有线串口设备列表
          if (_dataSource == 'usb') ...[
            Row(
              children: [
                const Text('USB 串口设备',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _listUsbDevices,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_usbDevices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                    '未发现 USB 串口设备\n请用 OTG 转接头插入 ELM327\n（CH340 / CP210x / PL2303 / FTDI / CDC）',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, height: 1.6)),
              )
            else
              ..._usbDevices.map((d) {
                final isConnecting = _usbConnectingId == d.vidPid;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.usb),
                    title: Text(d.label),
                    subtitle: Text('VID:PID ${d.vidPid}'),
                    trailing: isConnecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : null,
                    onTap: isConnecting ? null : () => _connectUsb(d),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}
