import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/vehicle/engine_pack_mapping.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = EngineSoundService.instance;
    _selected = svc.packId;
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
