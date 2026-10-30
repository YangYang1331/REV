import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_advice.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';
import 'package:obd_dashboard/core/diagnostic/symptom_index.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';

/// 症状自查（离线规则库）。
///
/// 勾症状 / 写一句"哪里不对劲" → 本地给出疑似故障码、严重度、能否继续开、
/// 参考费用与自查步骤。**全程不联网、不上传**，先解决 80% 的"车有异响/抖动"
/// 焦虑，再决定要不要去读真实 DTC 或进店。
class SymptomCheckScreen extends ConsumerStatefulWidget {
  const SymptomCheckScreen({super.key});

  @override
  ConsumerState<SymptomCheckScreen> createState() => _SymptomCheckScreenState();
}

class _SymptomCheckScreenState extends ConsumerState<SymptomCheckScreen> {
  final Set<String> _selected = {};
  final TextEditingController _text = TextEditingController();
  List<SuspectCode> _results = const [];
  bool _analyzed = false;
  String? _expanded;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _run() {
    setState(() {
      _results = SymptomIndex.match(
        symptomIds: _selected,
        freeText: _text.text,
      );
      _analyzed = true;
      _expanded = null;
    });
    FocusScope.of(context).unfocus();
  }

  void _reset() {
    setState(() {
      _selected.clear();
      _text.clear();
      _results = const [];
      _analyzed = false;
      _expanded = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('症状自查'),
        actions: [
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _intro(skin),
          const SizedBox(height: 14),
          Text('勾选症状（可多选）',
              style: TextStyle(
                  color: skin.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SymptomIndex.symptoms)
                FilterChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 12)),
                  selected: _selected.contains(s.id),
                  onSelected: (on) {
                    setState(() {
                      if (on) {
                        _selected.add(s.id);
                      } else {
                        _selected.remove(s.id);
                      }
                    });
                    if (_analyzed) _run();
                  },
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  selectedColor: skin.accent.withValues(alpha: 0.22),
                  checkmarkColor: skin.accent,
                  side: BorderSide(
                      color: _selected.contains(s.id)
                          ? skin.accent.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.08)),
                  labelStyle: TextStyle(
                      color: _selected.contains(s.id) ? skin.ink : skin.dim),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: skin.ink, fontSize: 13),
            decoration: InputDecoration(
              hintText: '也可以直接描述：冷车要打三次才着，等红灯方向盘抖…',
              hintStyle: TextStyle(color: skin.faint, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: skin.panelStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: skin.panelStroke),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_selected.isEmpty && _text.text.trim().isEmpty)
                      ? null
                      : _run,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('分析一下'),
                  style: FilledButton.styleFrom(
                      backgroundColor: skin.accent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 44)),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: skin.dim,
                    side: BorderSide(color: skin.panelStroke)),
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_analyzed) ...[
            Row(
              children: [
                Text('疑似故障码',
                    style: TextStyle(
                        color: skin.dim,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const Spacer(),
                Text('按可能性排序', style: TextStyle(color: skin.faint, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            if (_results.isEmpty)
              _empty(skin)
            else
              ..._results.asMap().entries.map((e) => _resultCard(skin, e.key, e.value)),
          ],
          const SizedBox(height: 16),
          Text(
            '说明：以上是人工整理的常见症状 → 故障码映射，只作排查方向，不是诊断结论。'
            '同一症状可能由多个部件引起，确诊请连接 OBD 读取真实故障码或到店检查。',
            style: TextStyle(color: skin.faint, fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _intro(SkinDescriptor skin) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: skin.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.psychology_alt_outlined, color: skin.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '车有异响、抖动、打不着？先在这里自查。\n'
                '规则库在本机运行，不联网、不上传任何描述。',
                style: TextStyle(color: skin.ink, fontSize: 12.5, height: 1.6),
              ),
            ),
          ],
        ),
      );

  Widget _empty(SkinDescriptor skin) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '没有匹配到常见故障码。建议连接 OBD 读取真实 DTC（诊断 / 故障码页），'
          '或换一种说法再描述一次。',
          style: TextStyle(color: skin.dim, fontSize: 12, height: 1.6),
        ),
      );

  Color _sevColor(SkinDescriptor skin, DtcAdvice a) => switch (a.severity) {
        2 => skin.bad,
        1 => skin.warn,
        _ => skin.ok,
      };

  Widget _resultCard(SkinDescriptor skin, int rank, SuspectCode s) {
    final info = DtcDatabase.explain(s.code);
    final advice = s.advice;
    final color = _sevColor(skin, advice);
    final expanded = _expanded == s.code;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(
                () => _expanded = expanded ? null : s.code),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('${rank + 1}',
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Text(s.code,
                          style: TextStyle(
                              color: skin.accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(info.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: skin.ink, fontSize: 13)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(advice.severityLabel,
                            style: TextStyle(
                                color: color, fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (s.reasons.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final r in s.reasons)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: skin.accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(r,
                                style: TextStyle(
                                    color: skin.dim, fontSize: 10.5)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.directions_car, size: 14, color: skin.dim),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          advice.canDrive,
                          maxLines: expanded ? 20 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: skin.dim, fontSize: 11.5, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.payments_outlined, size: 14, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('参考费用：${advice.cost}',
                            style: TextStyle(
                                color: color, fontSize: 11.5)),
                      ),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: skin.faint),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.white.withValues(alpha: 0.08)),
                  Text('可以先自己查这几步',
                      style: TextStyle(
                          color: skin.dim,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...advice.selfCheck.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e.key + 1}. ',
                                style:
                                    TextStyle(color: color, fontSize: 11.5)),
                            Expanded(
                              child: Text(e.value,
                                  style: TextStyle(
                                      color: skin.dim,
                                      fontSize: 11.5,
                                      height: 1.45)),
                            ),
                          ],
                        ),
                      )),
                  if (advice.tip != null) ...[
                    const SizedBox(height: 4),
                    Text('提示：${advice.tip!}',
                        style: TextStyle(
                            color: skin.accent,
                            fontSize: 11,
                            height: 1.5)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
