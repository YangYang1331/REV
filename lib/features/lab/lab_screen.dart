import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:obd_dashboard/core/game/game_telemetry.dart';
import 'package:obd_dashboard/core/input/gear_shift_map.dart';
import 'package:obd_dashboard/core/perf/dyno_estimator.dart';
import 'package:obd_dashboard/core/rules/trigger_engine.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/track/track_line_detector.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/services/csv_recorder.dart';
import 'package:obd_dashboard/services/game_udp_service.dart';
import 'package:obd_dashboard/services/gamepad_input_service.dart';
import 'package:obd_dashboard/services/logcat_channel.dart';
import 'package:obd_dashboard/services/tts_service.dart';

/// 扩展实验室：游戏 UDP / 手柄换挡 / 自动圈速 / 车机直连 / CSV / Trigger /
/// OLED 省电 / 限速 / 马力估算 的统一入口。
class LabScreen extends ConsumerStatefulWidget {
  const LabScreen({super.key});

  @override
  ConsumerState<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends ConsumerState<LabScreen> {
  final _csv = CsvRecorder();
  final _logcat = LogcatChannel();
  final _track = TrackLineDetector();
  Timer? _tick;
  late final GameUdpService _gameTelemetry;

  GameProtocol? _proto;
  final TriggerEngine _engine = TriggerEngine(rules: const [
    TriggerRule(
        id: 'hot',
        metric: TriggerMetric.coolant,
        op: TriggerOp.above,
        threshold: 105,
        action: TriggerAction(redScreen: true, announce: true)),
    TriggerRule(
        id: 'rev',
        metric: TriggerMetric.rpm,
        op: TriggerOp.above,
        threshold: 6800,
        action: TriggerAction(shiftLamp: true)),
  ]);

  String _logcatNote = '未启动';
  bool _oledSave = false;
  int _speedLimit = 0;

  @override
  void initState() {
    super.initState();
    final tele = ref.read(telemetryProvider);
    GamepadInputService.instance.attach(tele);
    _gameTelemetry = GameUdpService(telemetry: tele);
    AppStore.instance.getOledPowerSave().then((v) => setState(() => _oledSave = v));
    AppStore.instance.getSpeedLimitKmh().then((v) => setState(() => _speedLimit = v));
    // 每 200ms 喂 CSV / Trigger / 自动圈速。
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
  }

  void _onTick() {
    final tele = ref.read(telemetryProvider);
    final d = tele.current;
    if (_csv.isRecording) _csv.feed(d);
    final outcome = _engine.update(TriggerSample(
      coolant: d.coolant,
      rpm: d.rpm.toDouble(),
      voltage: d.voltage,
      speed: d.speed,
    ));
    // 真实 TTS：仅在规则穿越边沿播报一次，不重复刷屏。
    if (outcome.justFired.announce) {
      final msg = _engine.rules
          .where((r) =>
              outcome.activeIds.contains(r.id) && r.action.announce)
          .map((r) => _announceText(r))
          .where((s) => s.isNotEmpty)
          .join('；');
      if (msg.isNotEmpty) TtsService.instance.speak(msg);
    }
    // 自动圈速：用 GPS 经纬度。
    final lat = tele.lastLat;
    final lng = tele.lastLng;
    if (lat != null && lng != null) {
      final res = _track.feed(lat, lng, d.speed,
          DateTime.now().millisecondsSinceEpoch.toDouble());
      if (res != null) {
        setState(() {});
      }
    }
    if (mounted) setState(() {});
  }

  /// 根据触发规则生成口语化播报文案。
  String _announceText(TriggerRule r) {
    final metricName = switch (r.metric) {
      TriggerMetric.coolant => '水温',
      TriggerMetric.rpm => '转速',
      TriggerMetric.voltage => '电压',
      TriggerMetric.speed => '车速',
      TriggerMetric.oilTemp => '油温',
    };
    final dir = r.op == TriggerOp.above ? '过高' : '过低';
    return '$metricName$dir，请注意';
  }

  @override
  void dispose() {
    _tick?.cancel();
    _gameTelemetry.stop();
    _csv.stop();
    _logcat.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final tele = ref.watch(telemetryProvider);
    final d = tele.current;
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('扩展实验室 v2.14')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(skin, '游戏 UDP 遥测'),
          ...GameProtocol.values.map((p) => ListTile(
                dense: true,
                leading: const Icon(Icons.videogame_asset,
                    color: Color(0xFF27D6E6), size: 20),
                title: Text('${p.label}  :${p.port}',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: Text(p.hint,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11, height: 1.4)),
                trailing: _proto == p && _gameTelemetry.isRunning
                    ? const Text('监听中',
                        style: TextStyle(color: Colors.green, fontSize: 11))
                    : null,
                onTap: () => _toggleGame(p),
              )),
          Text('已收包: ${_gameTelemetry.packets} 帧',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          _section(skin, '蓝牙手柄换挡'),
          ValueListenableBuilder<GearShiftMap>(
            valueListenable: GamepadInputService.instance.notifier,
            builder: (_, m, __) {
              final upKey = m.assignments.entries
                  .where((e) => e.value == ShiftAction.up)
                  .map((e) => e.key)
                  .join(',');
              final dnKey = m.assignments.entries
                  .where((e) => e.value == ShiftAction.down)
                  .map((e) => e.key)
                  .join(',');
              return Column(children: [
                ListTile(
                  dense: true,
                  title: Text('升挡键: $upKey',
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                  trailing: TextButton(
                    onPressed: () {
                      GamepadInputService.instance.startBinding(ShiftAction.up);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请按一下手柄上要设为升挡的键')));
                    },
                    child: const Text('重设',
                        style: TextStyle(color: Color(0xFF27D6E6), fontSize: 12)),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text('降挡键: $dnKey',
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                  trailing: TextButton(
                    onPressed: () {
                      GamepadInputService.instance.startBinding(ShiftAction.down);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请按一下手柄上要设为降挡的键')));
                    },
                    child: const Text('重设',
                        style: TextStyle(color: Color(0xFF27D6E6), fontSize: 12)),
                  ),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      onPressed: () => tele.nudgeGear(-1),
                      icon: const Icon(Icons.remove, color: Colors.white)),
                  Text('当前挡 ${d.gear}',
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  IconButton(
                      onPressed: () => tele.nudgeGear(1),
                      icon: const Icon(Icons.add, color: Colors.white)),
                  TextButton(
                      onPressed: () => tele.clearManualGear(),
                      child: const Text('清除手动',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11))),
                ]),
              ]);
            },
          ),
          _section(skin, '赛道自动识别圈速'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.flag, color: Color(0xFFFF6B3D), size: 20),
            title: Text(_track.hasOrigin
                ? '起点线已学习 · 已完成 ${_track.lapCount} 圈'
                : '在起点线处点此学习 S/F 线',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(
                '自动计圈基于 GPS 穿越起点半径；${tele.lastLat == null ? '等待 GPS…' : 'GPS 在线'}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: ElevatedButton(
              onPressed: () {
                final lat = tele.lastLat;
                final lng = tele.lastLng;
                if (lat == null || lng == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('暂无 GPS，请在室外定位后再学习起点线')));
                  return;
                }
                setState(() => _track.learnOrigin(lat, lng));
              },
              child: const Text('学习起点'),
            ),
          ),
          _section(skin, '车机直连数据（logcat / CAN）'),
          SwitchListTile(
            dense: true,
            title: const Text('启用 logcat 通道',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(_logcatNote,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11, height: 1.4)),
            value: _logcat.isRunning,
            onChanged: (v) async {
              if (v) {
                final ok = await _logcat.start();
                if (!mounted) return;
                setState(() => _logcatNote = _logcat.statusNote);
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '普通应用读不到系统 logcat：需 ADB 授权或系统签名车机。\n${_logcat.statusNote}')));
                }
              } else {
                await _logcat.stop();
                setState(() => _logcatNote = _logcat.statusNote);
              }
            },
          ),
          _section(skin, '实时 PID 导出 CSV'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.save_alt, color: Color(0xFF27D6E6), size: 20),
            title: Text(_csv.isRecording
                ? '录制中… 已 ${_csv.rows} 行'
                : '开始录制（时间/RPM/车速/水温/电压/挡位）',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            trailing: ElevatedButton(
              onPressed: () async {
                if (_csv.isRecording) {
                  final path = await _csv.stop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已保存 $path')));
                  }
                } else {
                  await _csv.start();
                }
                setState(() {});
              },
              child: Text(_csv.isRecording ? '结束' : '开始'),
            ),
          ),
          _section(skin, 'Trigger → Action'),
          const ListTile(
            dense: true,
            title: Text('默认规则：水温>105℃ 红屏并语音；转速>6800 换挡灯',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text('越过阈值时走系统 TTS 语音播报（仅触发一次，回落自动复位）',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          SwitchListTile(
            dense: true,
            secondary: const Icon(Icons.record_voice_over,
                color: Color(0xFF27D6E6), size: 20),
            title: const Text('语音播报开关',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            value: TtsService.instance.isEnabled,
            onChanged: (v) => setState(
                () => TtsService.instance.setEnabled(v)),
          ),
          _section(skin, 'OLED 省电 / 限速 / 马力估算'),
          SwitchListTile(
            dense: true,
            title: const Text('OLED 纯黑省电',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: const Text('纯黑背景降低自发光功耗（需主题配合）',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: _oledSave,
            onChanged: (v) async {
              await AppStore.instance.setOledPowerSave(v);
              setState(() => _oledSave = v);
            },
          ),
          ListTile(
            dense: true,
            title: Text('限速提醒: ${_speedLimit == 0 ? '关' : '$_speedLimit km/h'}',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            trailing: TextButton(
              onPressed: () async {
                final c = TextEditingController(
                    text: _speedLimit.toString());
                final r = await showDialog<int>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF11161D),
                    title: const Text('设定限速 km/h（0=关）',
                        style: TextStyle(color: Colors.white)),
                    content: TextField(
                        controller: c,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0),
                          child: const Text('保存')),
                    ],
                  ),
                );
                if (r != null) {
                  await AppStore.instance.setSpeedLimitKmh(r);
                  setState(() => _speedLimit = r);
                }
              },
              child: const Text('设定',
                  style: TextStyle(color: Color(0xFF27D6E6), fontSize: 12)),
            ),
          ),
          Builder(builder: (_) {
            final est = DynoEstimator.estimate(
              const DynoInputs(massKg: 1500, drivetrainEfficiency: 0.85),
              d.accelG == null ? 0 : d.accelG! * 9.81,
              d.speed / 3.6,
              d.rpm.toDouble(),
            );
            return ListTile(
              dense: true,
              leading: const Icon(Icons.bolt, color: Color(0xFFFF6B3D), size: 20),
              title: Text(
                  '估算曲轴马力: ~${est.crankHp.round()} hp（区间 ${est.crankHpLow.round()}~${est.crankHpHigh.round()}）',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: const Text('估算值：车重 1500kg、传动效率 0.85；非马力机实测',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            );
          }),
          _section(skin, '皮肤描述符 JSON'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.palette, color: Color(0xFFFF6B3D), size: 20),
            title: Text('导出当前皮肤「${skin.id}」为 JSON',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: const Text('导出色板/布局到文件供分享；内置皮肤仍在设置里切换',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: ElevatedButton(
              onPressed: () async {
                final map = {
                  'id': skin.id,
                  'label': skin.id,
                  'layout': skin.layout.name,
                  'background': '#${skin.background.value.toRadixString(16)}',
                  'accent': '#${skin.accent.value.toRadixString(16)}',
                  'ink': '#${skin.ink.value.toRadixString(16)}',
                };
                final dir = await getExternalStorageDirectory() ??
                    await getApplicationDocumentsDirectory();
                final f = File('${dir.path}/rev_skin_${skin.id}.json');
                await f.writeAsString(jsonEncode(map));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('已导出 ${f.path}')));
                }
              },
              child: const Text('导出'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(skin, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      );

  Future<void> _toggleGame(GameProtocol p) async {
    if (_proto == p && _gameTelemetry.isRunning) {
      await _gameTelemetry.stop();
      setState(() => _proto = null);
    } else {
      try {
        await _gameTelemetry.start(p);
        setState(() => _proto = p);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('端口 ${p.port} 绑定失败：$e')));
        }
      }
    }
  }
}
