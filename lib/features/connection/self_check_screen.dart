import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/connection/scan_logic.dart';
import 'package:obd_dashboard/services/ble_uart_channel.dart';
import 'package:obd_dashboard/services/obd_service.dart';

/// 步骤执行失败的业务异常（message 直接展示给用户）。
class _Fail implements Exception {
  _Fail(this.message);
  final String message;
}

enum _StepStatus { pending, running, pass, fail }

class _Step {
  _Step(this.title);
  final String title;
  _StepStatus status = _StepStatus.pending;
  String detail = '';
}

/// 连接自检页（短板5）：分步排查 蓝牙开关 → 权限 → 扫描 → 连接 → ELM 初始化 → OBD 协议。
/// 进入页面自动按序执行，可整体重试。
class SelfCheckScreen extends ConsumerStatefulWidget {
  const SelfCheckScreen({super.key});

  @override
  ConsumerState<SelfCheckScreen> createState() => _SelfCheckScreenState();
}

class _SelfCheckScreenState extends ConsumerState<SelfCheckScreen> {
  late final List<_Step> _steps = [
    _Step('蓝牙开关'),
    _Step('蓝牙 / 定位权限'),
    _Step('BLE 扫描'),
    _Step('设备连接（GATT）'),
    _Step('ELM327 初始化'),
    _Step('OBD 协议握手'),
  ];

  bool _running = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _runAll() async {
    if (_running) return;
    _running = true;
    _started = true;
    setState(() {
      for (final s in _steps) {
        s.status = _StepStatus.pending;
        s.detail = '';
      }
    });
    final obd = ref.read(obdServiceProvider);

    // ① 蓝牙开关
    await _run(0, () async {
      final st = FlutterBluePlus.adapterStateNow;
      if (st == BluetoothAdapterState.on) return '蓝牙已开启';
      throw _Fail('蓝牙未开启（当前：${st.name}），请下拉系统栏打开蓝牙后点"重新检测"');
    });
    if (!mounted) return;
    if (_steps[0].status == _StepStatus.fail) return _finish();

    // ② 权限
    await _run(1, () async {
      final ok = await ScanLogic.ensurePermissions();
      if (ok) return '蓝牙 / 定位权限已授予';
      throw _Fail('权限被拒绝，请在系统设置中允许"附近的蓝牙设备"与定位权限');
    });
    if (!mounted) return;
    if (_steps[1].status == _StepStatus.fail) return _finish();

    // ③ 扫描（12s，实时显示发现数量）
    await _run(2, () async {
      await ScanLogic.startScan((list) {
        if (!mounted) return;
        setState(() => _steps[2].detail = '已发现 ${list.length} 台 BLE 设备…');
      });
      final n = ScanLogic.lastResults.length;
      if (n == 0) {
        throw _Fail('12 秒内未发现任何 BLE 设备，请确认 ELM327 已插好并上电（指示灯亮）');
      }
      return '共发现 $n 台 BLE 设备';
    });
    if (!mounted) return;
    if (_steps[2].status == _StepStatus.fail) return _finish();

    // 选目标设备：优先已记忆设备，否则取第一台
    BluetoothDevice? target;
    final knownId = await AppStore.instance.getKnownDeviceId();
    if (knownId != null && knownId.isNotEmpty) {
      for (final d in ScanLogic.lastResults) {
        if (d.remoteId.str == knownId) {
          target = d;
          break;
        }
      }
    }
    target ??=
        ScanLogic.lastResults.isEmpty ? null : ScanLogic.lastResults.first;

    // ④ GATT 连接：进入 initializing（或已 polling）即通过
    await _run(3, () async {
      if (obd.isConnected) return '已处于连接状态，跳过连接';
      if (target == null) throw _Fail('没有可连接的 BLE 设备');
      final name = target.platformName.isEmpty
          ? target.remoteId.str
          : target.platformName;
      // 后台发起连接，同时观察 connState 阶段跳转
      unawaited(obd.connect(BleUartChannel.forDevice(target)));
      final ok = await _waitStage(obd,
          const {ObdConnStage.initializing, ObdConnStage.polling},
          const Duration(seconds: 15));
      if (!ok) {
        throw _Fail(obd.connState.value.lastError ?? 'GATT 连接超时（15s），请靠近设备后重试');
      }
      return '已连接 $name';
    });
    if (!mounted) return;
    if (_steps[3].status == _StepStatus.fail) return _finish();

    // ⑤ ELM 初始化：已进入 initializing 阶段即视为初始化序列已下发
    await _run(4, () async {
      await Future.delayed(const Duration(milliseconds: 500));
      final st = obd.connState.value.stage;
      if (st == ObdConnStage.initializing || st == ObdConnStage.polling) {
        return 'ELM327 初始化序列（ATZ / ATE0 / ATSP6…）已下发';
      }
      throw _Fail(obd.connState.value.lastError ?? '未进入初始化阶段');
    });
    if (!mounted) return;
    if (_steps[4].status == _StepStatus.fail) return _finish();

    // ⑥ 协议握手：进入 polling 即数据通道成功
    await _run(5, () async {
      final ok = await _waitStage(
          obd, const {ObdConnStage.polling}, const Duration(seconds: 25));
      if (!ok) {
        throw _Fail(obd.connState.value.lastError ?? '协议握手超时（25s），未进入数据轮询');
      }
      return 'OBD-II 数据通道已建立，实时采集中';
    });
    if (!mounted) return;
    _finish();
  }

  void _finish() {
    _running = false;
    if (mounted) setState(() {});
  }

  Future<void> _run(int i, Future<String> Function() body) async {
    if (!mounted) return;
    setState(() => _steps[i].status = _StepStatus.running);
    try {
      final detail = await body();
      if (!mounted) return;
      setState(() {
        _steps[i].status = _StepStatus.pass;
        _steps[i].detail = detail;
      });
    } on _Fail catch (e) {
      if (!mounted) return;
      setState(() {
        _steps[i].status = _StepStatus.fail;
        _steps[i].detail = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _steps[i].status = _StepStatus.fail;
        _steps[i].detail = '异常：$e';
      });
    }
  }

  /// 等待 connState 进入目标阶段；进入 disconnected/reconnecting 视为失败；超时失败。
  Future<bool> _waitStage(
      ObdService obd, Set<ObdConnStage> targets, Duration timeout) {
    final completer = Completer<bool>();
    void check() {
      if (completer.isCompleted) return;
      final st = obd.connState.value.stage;
      if (targets.contains(st)) {
        completer.complete(true);
      } else if (st == ObdConnStage.disconnected ||
          st == ObdConnStage.reconnecting) {
        completer.complete(false);
      }
    }

    obd.connState.addListener(check);
    check();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future.whenComplete(() {
      timer.cancel();
      obd.connState.removeListener(check);
    });
  }

  Widget _leading(_Step s) {
    switch (s.status) {
      case _StepStatus.pending:
        return const Icon(Icons.radio_button_unchecked,
            color: Colors.white24, size: 22);
      case _StepStatus.running:
        return const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF27D6E6)),
        );
      case _StepStatus.pass:
        return const Icon(Icons.check_circle,
            color: Color(0xFF2EE68A), size: 22);
      case _StepStatus.fail:
        return const Icon(Icons.cancel, color: Color(0xFFFF5C5C), size: 22);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPass = _started && _steps.every((s) => s.status == _StepStatus.pass);
    final anyFail = _started && _steps.any((s) => s.status == _StepStatus.fail);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('连接自检'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '自动按序排查蓝牙链路，定位连接失败原因',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          ..._steps.map((s) => Card(
                color: const Color(0xFF111823),
                child: ListTile(
                  leading: _leading(s),
                  title: Text(s.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  subtitle: s.detail.isEmpty
                      ? const Text('待执行',
                          style: TextStyle(color: Colors.white24, fontSize: 12))
                      : Text(
                          s.detail,
                          style: TextStyle(
                            color: s.status == _StepStatus.fail
                                ? const Color(0xFFFFB4B4)
                                : Colors.white54,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                ),
              )),
          const SizedBox(height: 12),
          if (allPass)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x222EE68A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: Color(0xFF2EE68A), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('全部通过，数据链路正常，可返回查看仪表盘',
                        style: TextStyle(color: Color(0xFFB8F5D4), fontSize: 13)),
                  ),
                ],
              ),
            ),
          if (anyFail)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x22FF5C5C),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Color(0xFFFF8A8A), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('存在未通过项，请按红色提示处理后点"重新检测"',
                        style: TextStyle(color: Color(0xFFFFC4C4), fontSize: 13)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B3D),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _running ? null : _runAll,
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_running ? '检测中…' : '重新检测'),
            ),
          ),
        ],
      ),
    );
  }
}
