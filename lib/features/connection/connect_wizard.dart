import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/connection/scan_logic.dart';
import 'package:obd_dashboard/services/ble_uart_channel.dart';
import 'package:obd_dashboard/services/usb_uart_channel.dart';
import 'package:obd_dashboard/services/wifi_obd_channel.dart';

/// 首次连接向导：把"自己猜怎么连、用什么协议、什么车型"收敛成一条直线。
///
/// 四步：选方式 → 选设备 → 连接并自动试协议 → 读 VIN 匹配车型。
/// 任何一步失败都能原地重试，不会把用户卡在空白页；VIN 读不到也可以跳过。
class ConnectWizard extends ConsumerStatefulWidget {
  const ConnectWizard({super.key});
  @override
  ConsumerState<ConnectWizard> createState() => _ConnectWizardState();
}

enum _Step { pickType, pickDevice, connecting, vin, done }

class _ConnectWizardState extends ConsumerState<ConnectWizard> {
  _Step _step = _Step.pickType;
  String _type = 'ble'; // ble / usb / wifi

  List<BluetoothDevice> _ble = [];
  List<UsbObdDevice> _usb = [];
  bool _scanning = false;

  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '35000');

  BluetoothDevice? _selectedBle;
  UsbObdDevice? _selectedUsb;

  String _status = '';
  bool _ok = false;
  String? _vin;
  String? _matchedName;

  @override
  void dispose() {
    ScanLogic.stopScan();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _status = '正在扫描…';
      _ble = [];
      _usb = [];
    });
    if (_type == 'usb') {
      try {
        final l = await UsbUartChannel.listObdDevices();
        if (mounted) {
          setState(() {
            _usb = l;
            _scanning = false;
            _status = l.isEmpty ? '没有检测到 USB 串口设备，检查 OTG 转接头与线材' : '';
          });
        }
      } catch (e) {
        if (mounted) setState(() {
          _scanning = false;
          _status = 'USB 枚举失败：$e';
        });
      }
      return;
    }
    try {
      await ScanLogic.startScan((list) {
        if (!mounted) return;
        setState(() {
          _ble = list;
          _status = list.isEmpty ? '正在扫描…' : '';
        });
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          if (_ble.isEmpty && _status.isEmpty) _status = '没找到设备，确认适配器已通电（钥匙 ON）';
        });
      }
    }
  }

  Future<void> _connect() async {
    setState(() {
      _step = _Step.connecting;
      _status = '正在连接并自动识别协议（约 10–20 秒）…';
      _ok = false;
    });
    await ScanLogic.stopScan();
    final obd = ref.read(obdServiceProvider);
    var ok = false;
    try {
      if (_type == 'ble' && _selectedBle != null) {
        ok = await obd.connect(BleUartChannel.forDevice(_selectedBle!));
      } else if (_type == 'usb' && _selectedUsb != null) {
        ok = await obd.connect(UsbUartChannel.forDevice(_selectedUsb!.device));
      } else if (_type == 'wifi') {
        final host = _hostCtrl.text.trim();
        final port = int.tryParse(_portCtrl.text.trim()) ?? 35000;
        if (host.isEmpty) {
          setState(() {
            _status = '请先填 WiFi 适配器的 IP';
            _ok = false;
          });
          return;
        }
        ok = await obd.connect(WifiObdChannel.single(host, port));
      }
    } catch (e) {
      ok = false;
      _status = '连接异常：$e';
    }
    if (!mounted) return;
    setState(() {
      _ok = ok;
      _step = _Step.vin;
      _status = ok ? '已连接，正在读取车架号…' : '连接失败：确认点火开关在 ON 档、适配器指示灯常亮，然后重试';
    });
    if (ok) await _readVin();
  }

  Future<void> _readVin() async {
    final obd = ref.read(obdServiceProvider);
    try {
      final info = await obd.readVin();
      if (!mounted) return;
      if (info == null) {
        setState(() => _status = '连接成功，但这台车不支持读 VIN（不影响使用，可以手动选车型）');
        return;
      }
      final pid = info.matchProfileId();
      if (pid != null) {
        ref.read(telemetryProvider).setProfile(VehicleProfile.byId(pid));
      }
      setState(() {
        _vin = info.vin;
        _matchedName = pid == null ? null : VehicleProfile.byId(pid).name;
        _status = pid == null
            ? '读到 VIN ${info.vin}，车型库暂未覆盖，请到设置里手动选择'
            : '已自动匹配：${VehicleProfile.byId(pid).name}';
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '连接成功（VIN 读取失败：$e）';
        _step = _Step.done;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('连接向导'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _progress(skin),
          const SizedBox(height: 14),
          if (_step == _Step.pickType) _pickType(skin),
          if (_step == _Step.pickDevice) _pickDevice(skin),
          if (_step == _Step.connecting) _connectingView(skin),
          if (_step == _Step.vin || _step == _Step.done) _resultView(skin),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text(_status,
                  style: TextStyle(color: skin.dim, fontSize: 12.5, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progress(skin) {
    final idx = _step.index;
    const labels = ['选方式', '选设备', '连接', '读车型'];
    return Row(
      children: List.generate(labels.length, (i) {
        final on = i <= idx.clamp(0, 3);
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: on ? skin.accent2 : Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[i],
                  style: TextStyle(
                      color: on ? skin.accent2 : skin.faint, fontSize: 10)),
            ],
          ),
        );
      }),
    );
  }

  Widget _typeCard(skin, String id, IconData icon, String title, String sub) {
    final on = _type == id;
    return InkWell(
      onTap: () => setState(() => _type = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on
              ? skin.accent2.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? skin.accent2.withValues(alpha: 0.5) : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, color: on ? skin.accent2 : skin.dim, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: skin.ink, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(sub, style: TextStyle(color: skin.faint, fontSize: 11)),
                ],
              ),
            ),
            if (on) Icon(Icons.check_circle, color: skin.accent2, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _pickType(skin) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _typeCard(skin, 'ble', Icons.bluetooth, '蓝牙适配器（最常见）',
              'Vgate iCar Pro、ELM327 蓝牙版等，插上钥匙 ON 档即可'),
          _typeCard(skin, 'usb', Icons.usb, 'USB / OTG 有线', '最稳，不会掉线；需要 OTG 转接头'),
          _typeCard(skin, 'wifi', Icons.wifi, 'WiFi 适配器', '车机场景常用，需与手机同一热点'),
          const SizedBox(height: 8),
          if (_type == 'wifi') ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostCtrl,
                    style: TextStyle(color: skin.ink, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '适配器 IP',
                      hintText: '192.168.0.10',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: skin.ink, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '端口',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('直接连接'),
            ),
          ] else
            FilledButton.icon(
              onPressed: () {
                setState(() => _step = _Step.pickDevice);
                _scan();
              },
              icon: const Icon(Icons.search, size: 18),
              label: const Text('下一步：扫描设备'),
            ),
          const SizedBox(height: 10),
          Text(
            '提示：不用向导也能用。直接去「连接」页手动连，成功一次之后 App 会记住这台适配器，'
            '下次冷启动自动重连。',
            style: TextStyle(color: skin.faint, fontSize: 11, height: 1.5),
          ),
        ],
      );

  Widget _pickDevice(skin) {
    final list = _type == 'usb' ? <Widget>[] : <Widget>[];
    if (_type == 'usb') {
      for (final d in _usb) {
        final on = _selectedUsb?.vidPid == d.vidPid;
        list.add(_deviceTile(skin, d.label, d.vidPid, on, () {
          setState(() => _selectedUsb = d);
        }));
      }
    } else {
      for (final d in _ble) {
        final on = _selectedBle?.remoteId == d.remoteId;
        final name = d.platformName.isEmpty ? d.remoteId.str : d.platformName;
        final hint = _looksLikeObd(name) ? '看起来是 OBD 适配器' : '未知设备';
        list.add(_deviceTile(skin, name, hint, on, () {
          setState(() => _selectedBle = d);
        }));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('发现的设备（${_type == 'usb' ? _usb.length : _ble.length}）',
                style: TextStyle(color: skin.dim, fontSize: 12)),
            const Spacer(),
            TextButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: Icon(_scanning ? Icons.hourglass_top : Icons.refresh, size: 16),
              label: Text(_scanning ? '扫描中…' : '重新扫描'),
            ),
          ],
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                _type == 'usb'
                    ? '没找到 USB 串口。确认 OTG 线插好、适配器供电正常。'
                    : '还没发现设备。适配器要在通电状态（钥匙 ON），手机蓝牙与定位权限都要允许。',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.faint, fontSize: 12, height: 1.5),
              ),
            ),
          )
        else
          ...list,
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_type == 'usb' ? _selectedUsb != null : _selectedBle != null)
              ? _connect
              : null,
          icon: const Icon(Icons.link, size: 18),
          label: const Text('连接并自动识别'),
        ),
        TextButton(
          onPressed: () => setState(() => _step = _Step.pickType),
          child: const Text('返回上一步'),
        ),
      ],
    );
  }

  bool _looksLikeObd(String name) {
    final n = name.toUpperCase();
    return n.contains('OBD') ||
        n.contains('ELM') ||
        n.contains('V-LINK') ||
        n.contains('VLINK') ||
        n.contains('ICAR') ||
        n.contains('VGATE') ||
        n.contains('KONNWEI');
  }

  Widget _deviceTile(
      skin, String title, String sub, bool on, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: on
              ? skin.accent2.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? skin.accent2.withValues(alpha: 0.5) : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18, color: on ? skin.accent2 : skin.faint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: skin.ink, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: skin.faint, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectingView(skin) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            CircularProgressIndicator(color: skin.accent2),
            const SizedBox(height: 16),
            Text('正在连接…', style: TextStyle(color: skin.dim, fontSize: 13)),
          ],
        ),
      );

  Widget _resultView(skin) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (_ok ? skin.ok : skin.bad).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (_ok ? skin.ok : skin.bad).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(_ok ? Icons.check_circle_outline : Icons.error_outline,
                    color: _ok ? skin.ok : skin.bad),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_ok ? '连接成功' : '连接失败',
                          style: TextStyle(
                              color: _ok ? skin.ok : skin.bad,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      if (_vin != null) ...[
                        const SizedBox(height: 4),
                        Text('VIN：$_vin', style: TextStyle(color: skin.dim, fontSize: 12)),
                      ],
                      if (_matchedName != null) ...[
                        const SizedBox(height: 2),
                        Text('车型档案：$_matchedName',
                            style: TextStyle(color: skin.dim, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_ok) ...[
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.dashboard_outlined, size: 18),
              label: const Text('开始使用'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _readVin,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新读取 VIN'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: () => setState(() => _step = _Step.pickDevice),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('先去连接页手动连'),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '适配器已被记住：下次冷启动或回到前台会自动重连（只需在设置里保持"自动重连"开启）。',
            style: TextStyle(color: skin.faint, fontSize: 11, height: 1.5),
          ),
        ],
      );
}
