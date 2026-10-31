import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/vehicle/engine_pack_mapping.dart';
import 'package:obd_dashboard/core/vehicle/engine_profile.dart';
import 'package:obd_dashboard/services/engine_sound_service.dart';

/// 引擎声浪引擎选择页：列出 manifest.packs，按 自吸/涡轮/机增/转子/电子
/// 分组显示；点选即试听怠速循环 2 秒。
class EnginePackScreen extends StatefulWidget {
  const EnginePackScreen({super.key});

  @override
  State<EnginePackScreen> createState() => _EnginePackScreenState();
}

class _EnginePackScreenState extends State<EnginePackScreen> {
  List<EnginePackManifest> _packs = [];
  String _selected = 'synth';
  bool _loading = true;
  EngineProfile _profile = EngineProfile.i4;
  EngineTuning _tuning = const EngineTuning();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = EngineSoundService.instance;
    _selected = svc.packId;
    _profile = svc.profile;
    _tuning = svc.tuning;
    var packs = await svc.loadManifest();
    packs = List.of(packs);
    // 始终把内置「电子/概念车」兜底放最后。
    if (!packs.any((p) => p.id == 'synth')) {
      packs.add(const EnginePackManifest(
          id: 'synth', name: '电子 / 概念车', synthOnly: true, bands: []));
    }
    if (!mounted) return;
    setState(() {
      _packs = packs;
      _loading = false;
    });
  }

  String _subtitle(EnginePackManifest p) {
    final tags = <String>[];
    if (p.id.startsWith('video_')) tags.add('视频采样');
    if (p.synthOnly) tags.add('实时合成');
    if (p.turbo) tags.add('涡轮');
    if (p.supercharged) tags.add('机增');
    if (p.hasPop) tags.add('放炮');
    if (p.hasBlowoff) tags.add('泄压阀');
    if (p.hasWhine) tags.add('啸叫');
    return tags.isEmpty ? '随转速播放' : tags.join(' · ');
  }

  Widget _tile(EnginePackManifest p) => RadioListTile<String>(
        activeColor: const Color(0xFF27D6E6),
        title: Text(p.name,
            style:
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(_subtitle(p),
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        value: p.id,
        groupValue: _selected,
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _selected = v);
          // ignore: discarded_futures
          EngineSoundService.instance.selectPack(v);
          if (!p.synthOnly) {
            // ignore: discarded_futures
            EngineSoundService.instance.previewPack(v);
          }
        },
      );

  Widget _tuningCard() {
    final svc = EngineSoundService.instance;
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 12);
    const valueStyle = TextStyle(color: Color(0xFF27D6E6), fontSize: 11);

    Widget slider({
      required String label,
      required double value,
      required double min,
      required double max,
      required String display,
      required EngineTuning Function(double v) build,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: labelStyle),
              const Spacer(),
              Text(display, style: valueStyle),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: const Color(0xFF27D6E6),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF27D6E6),
              overlayColor: const Color(0x2227D6E6),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                final t = build(v);
                setState(() => _tuning = t);
                svc.applyTuningLocal(t); // 拖动时即时试听，不写盘
              },
              onChangeEnd: (v) {
                final t = build(v);
                setState(() => _tuning = t);
                // ignore: discarded_futures
                svc.setTuning(t); // 松手才持久化
              },
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF121820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('合成引擎',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const Spacer(),
              Text(
                _selected == 'synth' ? '当前生效' : '选「电子/概念车」时生效',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in EngineProfile.all)
                ChoiceChip(
                  label: Text(p.name, style: const TextStyle(fontSize: 11)),
                  selected: _profile.id == p.id,
                  onSelected: (_) {
                    setState(() => _profile = p);
                    // ignore: discarded_futures
                    svc.setProfile(p.id);
                  },
                  selectedColor: const Color(0x3327D6E6),
                  backgroundColor: Colors.white10,
                  side: BorderSide(
                      color: _profile.id == p.id
                          ? const Color(0xFF27D6E6)
                          : Colors.white12),
                  labelStyle: TextStyle(
                      color: _profile.id == p.id
                          ? const Color(0xFF27D6E6)
                          : Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 2),
          slider(
            label: '亮度',
            value: _tuning.brightness,
            min: 0.6,
            max: 1.6,
            display: _tuning.brightness.toStringAsFixed(2),
            build: (v) => _tuning.copyWith(brightness: v),
          ),
          slider(
            label: '低频厚度',
            value: _tuning.lowEnd,
            min: 0.5,
            max: 1.6,
            display: _tuning.lowEnd.toStringAsFixed(2),
            build: (v) => _tuning.copyWith(lowEnd: v),
          ),
          slider(
            label: '颗粒感（失真）',
            value: _tuning.grit,
            min: 0,
            max: 1,
            display: '${(_tuning.grit * 100).round()}%',
            build: (v) => _tuning.copyWith(grit: v),
          ),
          slider(
            label: '回火放炮量',
            value: _tuning.popAmount,
            min: 0,
            max: 1,
            display: _tuning.popAmount <= 0.02
                ? '关闭'
                : '${(_tuning.popAmount * 100).round()}%',
            build: (v) => _tuning.copyWith(popAmount: v),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <EnginePackGroup, List<EnginePackManifest>>{};
    for (final p in _packs) {
      groups.putIfAbsent(enginePackGroup(p), () => []).add(p);
    }
    const order = [
      EnginePackGroup.na,
      EnginePackGroup.turbo,
      EnginePackGroup.supercharged,
      EnginePackGroup.rotary,
      EnginePackGroup.synth,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('引擎声浪引擎'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF27D6E6)))
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '点选即试听真实怠速声 2 秒；选择在仪表盘内实时生效。',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                _tuningCard(),
                for (final g in order)
                  if (groups.containsKey(g)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        enginePackGroupLabel(g),
                        style: const TextStyle(
                            color: Colors.white38,
                            fontWeight: FontWeight.w600,
                            fontSize: 12),
                      ),
                    ),
                    for (final p in groups[g]!) _tile(p),
                  ],
              ],
            ),
    );
  }
}
