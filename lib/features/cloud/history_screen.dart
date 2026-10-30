import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';

/// 云端历史趋势：水温 / 油温 / 电压 / 车速 的分钟级曲线。
///
/// 数据来自自己服务器 `/api/v1/history`（按设备、按登录账号鉴权），
/// 不接任何第三方统计服务；没配服务器或没登录时这里只显示说明。
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _hours = 24;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _points = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final cloud = ref.read(cloudServiceProvider);
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '需要先在「账号」里登录，历史数据按账号权限返回';
      });
      return;
    }
    final r = await cloud.fetchHistory(
        deviceId: cloud.deviceId, hours: _hours, token: auth.token);
    if (!mounted) return;
    if (r == null) {
      setState(() {
        _loading = false;
        _error = '拿不到历史数据：确认服务器已升级到 2.16.0，且本机在最近 $_hours 小时有上报';
      });
      return;
    }
    final pts = (r['points'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        <Map<String, dynamic>>[];
    setState(() {
      _points = pts;
      _loading = false;
      _error = pts.isEmpty ? '最近 $_hours 小时没有数据（车辆离线或未上报）' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('云端历史趋势'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [6, 24, 72, 168].map((h) {
              final on = _hours == h;
              return ChoiceChip(
                label: Text(h >= 24 ? '${h ~/ 24} 天' : '$h 小时',
                    style: TextStyle(
                        fontSize: 12,
                        color: on ? skin.background : skin.dim)),
                selected: on,
                selectedColor: skin.accent2,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                onSelected: (_) {
                  setState(() => _hours = h);
                  _load();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!,
                  style: TextStyle(color: skin.dim, fontSize: 12.5, height: 1.6)),
            )
          else ...[
            _chartCard(skin),
            const SizedBox(height: 14),
            _stats(skin),
          ],
        ],
      ),
    );
  }

  Widget _chartCard(SkinDescriptor skin) {
    const series = [
      ('ct', '水温', Color(0xFFFF6B3D)),
      ('ot', '油温', Color(0xFFF2B23B)),
      ('volt', '电压', Color(0xFF19E3FF)),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: series
                .map((s) => Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, color: s.$3),
                          const SizedBox(width: 5),
                          Text(s.$2,
                              style: TextStyle(color: skin.dim, fontSize: 11)),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: _HistoryPainter(
                points: _points,
                skin: skin,
                keys: const ['ct', 'ot', 'volt'],
                colors: const [
                  Color(0xFFFF6B3D),
                  Color(0xFFF2B23B),
                  Color(0xFF19E3FF),
                ],
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats(SkinDescriptor skin) {
    double? rangeOf(String key) {
      final vals = _points
          .map((p) => (p[key] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      return vals.isEmpty ? null : vals.last;
    }

    int? tsFirst = (_points.first['t'] as num?)?.toInt();
    int? tsLast = (_points.last['t'] as num?)?.toInt();
    String fmt(int? t) {
      if (t == null) return '--';
      final d = DateTime.fromMillisecondsSinceEpoch(t);
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('数据点 ${_points.length} · ${fmt(tsFirst)} → ${fmt(tsLast)}',
              style: TextStyle(color: skin.dim, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            '最新：水温 ${_f(rangeOf('ct'), '℃')} · 油温 ${_f(rangeOf('ot'), '℃')} '
            '· 电压 ${_f(rangeOf('volt'), 'V')} · 车速 ${_f(rangeOf('spd'), 'km/h')}',
            style: TextStyle(color: skin.ink, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 6),
          Text('曲线由服务端按分钟聚合（最多 500 个点），空档表示当时没有数据。',
              style: TextStyle(color: skin.faint, fontSize: 11)),
        ],
      ),
    );
  }

  String _f(double? v, String unit) =>
      v == null ? '--' : '${v.toStringAsFixed(v.abs() >= 100 ? 0 : 1)}$unit';
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({
    required this.points,
    required this.skin,
    required this.keys,
    required this.colors,
  });
  final List<Map<String, dynamic>> points;
  final SkinDescriptor skin;
  final List<String> keys;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    // 每条曲线独立归一化（水温/油温/电压量纲不同，共用坐标轴会被压扁）。
    for (var s = 0; s < keys.length; s++) {
      final key = keys[s];
      final values = <double?>[];
      for (final p in points) {
        values.add((p[key] as num?)?.toDouble());
      }
      final real = values.whereType<double>().toList();
      if (real.length < 2) continue;
      final min = real.reduce((a, b) => a < b ? a : b);
      final max = real.reduce((a, b) => a > b ? a : b);
      final span = (max - min) < 0.001 ? 1.0 : (max - min);

      final paint = Paint()
        ..color = colors[s % colors.length]
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      Path? path;
      double? prevX, prevY;
      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        final x = pad + w * (i / (values.length - 1));
        if (v == null) {
          prevX = null;
          continue;
        }
        final y = pad + h - (v - min) / span * h;
        if (prevX == null || prevY == null) {
          path ??= Path();
          path.moveTo(x, y);
        } else {
          path!.lineTo(x, y);
        }
        prevX = x;
        prevY = y;
      }
      if (path != null) canvas.drawPath(path, paint);
    }

    // 底部时间基线
    final axis = Paint()
      ..color = skin.faint.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(pad, size.height - pad), Offset(size.width - pad, size.height - pad), axis);
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter old) =>
      old.points.length != points.length || old.points != points;
}
