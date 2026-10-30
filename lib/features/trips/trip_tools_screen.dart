import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/trips/track_export.dart';

/// 行程工具：多选 → 合并 / 拆分 / 同路线对比。
///
/// 合并会把多段行程首尾拼成一段（中间熄火时会有一条直线连接）；
/// 拆分按轨迹点或时间比例切成两段；对比把两段的关键指标并排看。
class TripToolsScreen extends ConsumerStatefulWidget {
  const TripToolsScreen({super.key});

  @override
  ConsumerState<TripToolsScreen> createState() => _TripToolsScreenState();
}

class _TripToolsScreenState extends ConsumerState<TripToolsScreen> {
  List<TripRec> _trips = const [];
  final Set<int> _sel = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await AppStore.instance.loadTrips();
    l.sort((a, b) => b.ts.compareTo(a.ts));
    if (!mounted) return;
    setState(() {
      _trips = l;
      _sel.clear();
      _loading = false;
    });
  }

  List<int> get _selIdx => _sel.toList()..sort();

  List<TripRec> get _selTrips => [for (final i in _selIdx) _trips[i]];

  void _toggle(int i) {
    setState(() {
      if (!_sel.remove(i)) _sel.add(i);
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _compare() async {
    if (_selTrips.length != 2) return;
    final a = _selTrips[0];
    final b = _selTrips[1];
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => TripCompareScreen(a: a, b: b)));
  }

  Future<void> _merge() async {
    final picks = _selTrips;
    if (picks.length < 2) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('合并 ${picks.length} 段行程？'),
        content: const Text('里程、油耗、用时直接相加；轨迹按时间顺序首尾相接，'
            '中途熄火过的话会出现一条连接线。合并后原记录会被替换。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('合并')),
        ],
      ),
    );
    if (ok != true) return;
    final merged = TripOps.merge(picks);
    final keep = <TripRec>[];
    for (var i = 0; i < _trips.length; i++) {
      if (!_sel.contains(i)) keep.add(_trips[i]);
    }
    keep.add(merged);
    keep.sort((a, b) => b.ts.compareTo(a.ts));
    await AppStore.instance.saveTrips(keep);
    await _load();
    _toast('已合并为一段 · ${merged.km.toStringAsFixed(1)} km');
  }

  Future<void> _split() async {
    if (_selTrips.length != 1) return;
    final t = _selTrips.first;
    var f = 0.5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final parts = TripOps.split(t, f);
          return AlertDialog(
            title: const Text('拆分这段行程'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('按比例切分：${(f * 100).round()}% / ${100 - (f * 100).round()}%',
                    style: const TextStyle(fontSize: 13)),
                Slider(
                  value: f,
                  min: 0.1,
                  max: 0.9,
                  divisions: 16,
                  label: '${(f * 100).round()}%',
                  onChanged: (v) => setD(() => f = v),
                ),
                Text(
                  '前段 ${parts[0].km.toStringAsFixed(1)} km · '
                  '后段 ${parts[1].km.toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                const Text('有轨迹时按轨迹点切，否则按时间比例切；拆分后原记录会被替换。',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('拆分')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final parts = TripOps.split(t, f);
    final idx = _selIdx.first;
    final next = List<TripRec>.from(_trips)..removeAt(idx);
    next.addAll(parts);
    next.sort((a, b) => b.ts.compareTo(a.ts));
    await AppStore.instance.saveTrips(next);
    await _load();
    _toast('已拆成两段');
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('行程工具'),
      ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: skin.panel,
                  border: Border(
                      top: BorderSide(color: skin.panelStroke)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('已选 ${_sel.length} 段',
                          style: TextStyle(
                              color: skin.dim, fontSize: 12.5)),
                    ),
                    OutlinedButton(
                      onPressed: _selTrips.length == 2 ? _compare : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        foregroundColor: skin.accent,
                        side: BorderSide(
                            color: skin.accent.withValues(alpha: 0.4)),
                      ),
                      child: const Text('对比'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _selTrips.length >= 2 ? _merge : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        foregroundColor: skin.accent2,
                        side: BorderSide(
                            color: skin.accent2.withValues(alpha: 0.4)),
                      ),
                      child: const Text('合并'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _selTrips.length == 1 ? _split : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        foregroundColor: skin.warn,
                        side: BorderSide(
                            color: skin.warn.withValues(alpha: 0.4)),
                      ),
                      child: const Text('拆分'),
                    ),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? Center(
                  child: Text('暂无历史行程',
                      style: TextStyle(color: skin.faint, fontSize: 13)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    Text(
                      '勾选行程：选 1 段可拆分，选 2 段可对比，选多段可合并。',
                      style:
                          TextStyle(color: skin.dim, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _trips.length; i++)
                      _tripRow(skin, i, _trips[i]),
                  ],
                ),
    );
  }

  Widget _tripRow(SkinDescriptor skin, int i, TripRec t) {
    final on = _sel.contains(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: on
            ? skin.accent.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: on
                ? skin.accent.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggle(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                on ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: on ? skin.accent : skin.faint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmtTime(t.ts),
                        style: TextStyle(
                            color: skin.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${t.km.toStringAsFixed(1)} km · ${_fmtDuration(t.sec)} · '
                      '${t.l100 == null ? '油耗 --' : '${t.l100!.toStringAsFixed(1)} L/100'}'
                      ' · 评分 ${t.score ?? '--'}',
                      style: TextStyle(color: skin.faint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (t.track.length >= 2)
                Icon(Icons.route, size: 16, color: skin.accent2),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

String _fmtDuration(double sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = (sec % 60).round();
  if (h > 0) return '$h时${m}分';
  return '$m分${s.toString().padLeft(2, '0')}秒';
}

/// 两段行程并排对比（同路线历史对比也用这个）。
class TripCompareScreen extends ConsumerWidget {
  const TripCompareScreen({super.key, required this.a, required this.b});

  final TripRec a;
  final TripRec b;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(skinProvider);
    final rows = <_CmpRow>[
      _CmpRow.textOnly('开始时间', _fmtTs(a.ts), _fmtTs(b.ts)),
      _CmpRow('里程', '${a.km.toStringAsFixed(1)} km', '${b.km.toStringAsFixed(1)} km',
          a: a.km, b: b.km),
      _CmpRow('用时', _fmtDuration(a.sec), _fmtDuration(b.sec),
          a: a.sec, b: b.sec, lowerIsBetter: true),
      _CmpRow('平均车速', '${a.avgSpeed.toStringAsFixed(0)} km/h',
          '${b.avgSpeed.toStringAsFixed(0)} km/h',
          a: a.avgSpeed, b: b.avgSpeed),
      _CmpRow('最高车速', '${a.maxSpeed.toStringAsFixed(0)} km/h',
          '${b.maxSpeed.toStringAsFixed(0)} km/h',
          a: a.maxSpeed, b: b.maxSpeed),
      _CmpRow(
        '平均油耗',
        a.l100 == null ? '--' : '${a.l100!.toStringAsFixed(1)} L/100',
        b.l100 == null ? '--' : '${b.l100!.toStringAsFixed(1)} L/100',
        a: a.l100 ?? 0,
        b: b.l100 ?? 0,
        lowerIsBetter: true,
      ),
      _CmpRow(
        '驾驶评分',
        '${a.score ?? '--'}',
        '${b.score ?? '--'}',
        a: (a.score ?? 0).toDouble(),
        b: (b.score ?? 0).toDouble(),
      ),
      _CmpRow('急加速', '${a.harshAccel} 次', '${b.harshAccel} 次',
          a: a.harshAccel.toDouble(),
          b: b.harshAccel.toDouble(),
          lowerIsBetter: true),
      _CmpRow('急刹车', '${a.harshBrake} 次', '${b.harshBrake} 次',
          a: a.harshBrake.toDouble(),
          b: b.harshBrake.toDouble(),
          lowerIsBetter: true),
      _CmpRow('超速提醒', '${a.violations} 次', '${b.violations} 次',
          a: a.violations.toDouble(),
          b: b.violations.toDouble(),
          lowerIsBetter: true),
      _CmpRow(
        '怠速占比',
        _idlePct(a),
        _idlePct(b),
        a: a.sec > 0 ? a.idleSec / a.sec : 0,
        b: b.sec > 0 ? b.idleSec / b.sec : 0,
        lowerIsBetter: true,
      ),
    ];
    final similar = _routeSimilar(a, b);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('行程对比'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: similar
                  ? skin.ok.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: similar
                      ? skin.ok.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Icon(similar ? Icons.check_circle_outline : Icons.info_outline,
                    size: 18, color: similar ? skin.ok : skin.dim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    similar
                        ? '两段起终点接近，符合同路线对比（时间 / 油耗 / 驾驶风格）。'
                        : '两段起终点差得较远，里程油耗可比性一般，更适合比驾驶风格。',
                    style: TextStyle(
                        color: similar ? skin.ok : skin.dim,
                        fontSize: 11.5,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _header(skin),
                for (final r in rows) _row(skin, r),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '说明：对比只在两段记录之间算差值，不做路线匹配算法；'
            '起终点接近即视为同路线（约 300 m 内）。',
            style: TextStyle(color: skin.faint, fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _header(SkinDescriptor skin) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(
          children: [
            Expanded(
                flex: 4,
                child: Text('指标',
                    style: TextStyle(color: skin.dim, fontSize: 11))),
            Expanded(
                flex: 4,
                child: Text('A · ${_fmtShort(a.ts)}',
                    style: TextStyle(color: skin.accent, fontSize: 11))),
            Expanded(
                flex: 4,
                child: Text('B · ${_fmtShort(b.ts)}',
                    style: TextStyle(color: skin.accent2, fontSize: 11))),
            Expanded(
                flex: 3,
                child: Text('差值 (B-A)',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: skin.faint, fontSize: 11))),
          ],
        ),
      );

  Widget _row(SkinDescriptor skin, _CmpRow r) {
    final delta = r.b - r.a;
    final better = r.lowerIsBetter ? delta < 0 : delta > 0;
    final worse = r.lowerIsBetter ? delta > 0 : delta < 0;
    final dColor = !r.numeric
        ? skin.faint
        : better
            ? skin.ok
            : worse
                ? skin.warn
                : skin.dim;
    final dText = !r.numeric
        ? '—'
        : (delta.abs() < 0.05
            ? '持平'
            : '${delta > 0 ? '+' : '-'}${delta.abs().toStringAsFixed(1)}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
              flex: 4,
              child: Text(r.label,
                  style: TextStyle(color: skin.dim, fontSize: 11.5))),
          Expanded(
              flex: 4,
              child: Text(r.va,
                  style: TextStyle(color: skin.ink, fontSize: 11.5))),
          Expanded(
              flex: 4,
              child: Text(r.vb,
                  style: TextStyle(color: skin.ink, fontSize: 11.5))),
          Expanded(
            flex: 3,
            child: Text(dText,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: dColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  static String _idlePct(TripRec t) =>
      t.sec <= 0 ? '--' : '${(t.idleSec / t.sec * 100).toStringAsFixed(0)}%';

  static String _fmtTs(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _fmtShort(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// 起终点约 300 m 内认为同路线（不引入地图依赖的粗略判断）。
  static bool _routeSimilar(TripRec x, TripRec y) {
    if (x.track.isEmpty || y.track.isEmpty) return false;
    bool near(List<double> p, List<double> q) {
      if (p.length < 2 || q.length < 2) return false;
      final dLat = (p[0] - q[0]).abs() * 111000;
      final dLng = (p[1] - q[1]).abs() * 111000 * 0.8;
      return dLat * dLat + dLng * dLng <= 300 * 300;
    }

    return near(x.track.first, y.track.first) &&
        near(x.track.last, y.track.last);
  }
}

class _CmpRow {
  const _CmpRow(this.label, this.va, this.vb,
      {this.a = 0, this.b = 0, this.lowerIsBetter = false})
      : numeric = true;

  const _CmpRow.textOnly(this.label, this.va, this.vb)
      : a = 0,
        b = 0,
        lowerIsBetter = false,
        numeric = false;

  final String label;
  final String va;
  final String vb;
  final double a;
  final double b;
  final bool lowerIsBetter;
  final bool numeric;
}
