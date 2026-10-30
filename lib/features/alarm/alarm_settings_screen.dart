import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/services/alarm_service.dart';
import 'package:obd_dashboard/services/voice_service.dart';

/// 报警设置：阈值 + 语音/提示音开关 + 最近报警记录。
///
/// 阈值都写进 AppStore；保存后 [AlarmService] 立即生效（下一帧数据就按新阈值判定）。
class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  ConsumerState<AlarmSettingsScreen> createState() =>
      _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen> {
  late AlarmService _a;

  @override
  void initState() {
    super.initState();
    _a = AlarmService.instance;
    _a.restore();
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('报警与语音'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _a.save();
              if (!mounted) return;
              // 同步给遥测层：超速判定与仪表盘限速提醒共用同一个阈值。
              ref.read(telemetryProvider).speedLimitKmh = _a.speedLimitKmh;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已保存，下一帧生效')));
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _a,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _switchTile(skin, '启用报警', '关闭后不提示、不播报（数据仍记录）',
                _a.enabled, (v) => setState(() => _a.enabled = v)),
            _switchTile(skin, '语音播报', '用系统 TTS 念出告警内容（不联网）',
                _a.voice, (v) {
              setState(() => _a.voice = v);
              VoiceService.instance.setEnabled(v);
            }),
            _switchTile(skin, '提示音', '短促提示音 + 重震动',
                _a.soundEnabled, (v) => setState(() => _a.soundEnabled = v)),
            const SizedBox(height: 8),
            _section(skin, '阈值'),
            _slider(skin, '水温报警', _a.coolantHighC.toDouble(), 90, 120, '℃',
                (v) => setState(() => _a.coolantHighC = v.round())),
            _slider(skin, '机油温度报警', _a.oilHighC.toDouble(), 100, 160, '℃',
                (v) => setState(() => _a.oilHighC = v.round())),
            _slider(skin, '电压过低', _a.voltageLowV, 10.5, 13.0, 'V',
                (v) => setState(() => _a.voltageLowV = double.parse(v.toStringAsFixed(1))), decimals: 1),
            _slider(skin, '电压过高', _a.voltageHighV, 14.0, 16.0, 'V',
                (v) => setState(() => _a.voltageHighV = double.parse(v.toStringAsFixed(1))), decimals: 1),
            _slider(skin, '超速阈值（0=关闭）', _a.speedLimitKmh.toDouble(), 0, 160, 'km/h',
                (v) => setState(() => _a.speedLimitKmh = v.round())),
            const SizedBox(height: 8),
            _section(skin, '最近报警（最多 30 条）'),
            if (_a.log.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('暂无报警记录',
                      style: TextStyle(color: skin.faint, fontSize: 13)),
                ),
              )
            else
              ..._a.log.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (e.critical ? skin.bad : skin.warn)
                          .withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: (e.critical ? skin.bad : skin.warn)
                              .withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(e.critical ? Icons.warning_amber : Icons.info_outline,
                            size: 18, color: e.critical ? skin.bad : skin.warn),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e.title} · ${e.detail}',
                                  style: TextStyle(color: skin.ink, fontSize: 13)),
                              const SizedBox(height: 3),
                              Text(_fmt(e.ts),
                                  style: TextStyle(color: skin.faint, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            if (_a.log.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(_a.clearLog),
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('清空记录'),
              ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () =>
                  VoiceService.instance.speak('水温过高，一百零八度，请靠边停车检查', force: true),
              icon: const Icon(Icons.volume_up_outlined, size: 18),
              label: const Text('试听语音播报'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Widget _section(skin, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(title,
            style: TextStyle(
                color: skin.dim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );

  Widget _switchTile(skin, String title, String sub, bool v,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: v,
        onChanged: onChanged,
        title: Text(title, style: TextStyle(color: skin.ink, fontSize: 14)),
        subtitle: Text(sub, style: TextStyle(color: skin.faint, fontSize: 11)),
        activeColor: skin.accent2,
      );

  Widget _slider(skin, String label, double value, double min, double max,
      String unit, ValueChanged<double> onChanged,
      {int decimals = 0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: skin.ink, fontSize: 13)),
            const Spacer(),
            Text('${value.toStringAsFixed(decimals)} $unit',
                style: TextStyle(
                    color: skin.accent2,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) * (decimals == 0 ? 1 : 10)).round(),
          activeColor: skin.accent2,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
