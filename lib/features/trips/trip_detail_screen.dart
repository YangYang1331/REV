import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/trips/track_export.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// 单次行程详情：里程/油耗/评分/最高速/急加速急刹/怠速 + GPS 轨迹 + 导出。
class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({super.key, required this.trip});

  final TripRec trip;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  TripRec get trip => widget.trip;

  String _fmtTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtDuration(double sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = (sec % 60).round();
    if (h > 0) return '$h 小时 $m 分 ${s.toString().padLeft(2, '0')} 秒';
    return '$m 分 ${s.toString().padLeft(2, '0')} 秒';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  /// 导出本段行程为 CSV（含逐点轨迹），写进应用目录后直接调系统打开。
  Future<void> _exportCsv() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/rev-trip-${trip.ts}.csv');
      final b = StringBuffer()
        ..writeln('trip_start,${_fmtTime(trip.ts)}')
        ..writeln('distance_km,${trip.km.toStringAsFixed(2)}')
        ..writeln('fuel_l,${trip.fuel.toStringAsFixed(3)}')
        ..writeln('duration_s,${trip.sec.toStringAsFixed(0)}')
        ..writeln('avg_kmh,${trip.avgSpeed.toStringAsFixed(1)}')
        ..writeln('max_kmh,${trip.maxSpeed.toStringAsFixed(1)}')
        ..writeln('score,${trip.score ?? ''}')
        ..writeln('harsh_accel,${trip.harshAccel}')
        ..writeln('harsh_brake,${trip.harshBrake}')
        ..writeln('idle_s,${trip.idleSec.toStringAsFixed(0)}')
        ..writeln()
        ..writeln('lat,lng,speed_kmh');
      for (final p in trip.track) {
        if (p.length >= 2) {
          b.writeln('${p[0]},${p[1]},${p.length > 2 ? p[2] : ''}');
        }
      }
      await f.writeAsString(b.toString());
      _toast('已导出：${f.path.split('/').last}');
      await OpenFilex.open(f.path);
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 导出本段轨迹为 GPX / KML（Google Earth、奥维、运动 App 都能导入）。
  Future<void> _exportTrack(String kind) async {
    if (_busy) return;
    if (trip.track.length < 2) {
      _toast('这段行程没有轨迹点，无法导出');
      return;
    }
    setState(() => _busy = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/rev-trip-${trip.ts}.$kind');
      final text =
          kind == 'gpx' ? TrackExport.gpx(trip) : TrackExport.kml(trip);
      await f.writeAsString(text);
      _toast('已导出：${f.path.split('/').last}');
      await OpenFilex.open(f.path);
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 把统计卡片截成 PNG，方便直接发群里（不依赖任何第三方分享库）。
  Future<void> _saveCard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _toast('卡片还没准备好，请重试');
        return;
      }
      final img = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        _toast('生成图片失败');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/rev-trip-${trip.ts}.png');
      await f.writeAsBytes(bytes.buffer.asUint8List());
      _toast('分享卡片已保存：${f.path.split('/').last}');
      await OpenFilex.open(f.path);
    } catch (e) {
      _toast('生成失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final l100 = trip.l100;
    final score = trip.score;
    final scoreColor = score == null
        ? skin.dim
        : score >= 90
            ? skin.ok
            : score >= 75
                ? skin.warn
                : skin.bad;

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('行程详情'),
        actions: [
          IconButton(
            tooltip: '导出 CSV',
            onPressed: _busy ? null : _exportCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '导出轨迹',
            enabled: !_busy,
            icon: const Icon(Icons.route_outlined),
            onSelected: _exportTrack,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'gpx',
                enabled: trip.track.length >= 2,
                child: const Text('导出 GPX（轨迹）'),
              ),
              PopupMenuItem(
                value: 'kml',
                enabled: trip.track.length >= 2,
                child: const Text('导出 KML（Google Earth）'),
              ),
            ],
          ),
          IconButton(
            tooltip: '生成分享卡片',
            onPressed: _busy ? null : _saveCard,
            icon: const Icon(Icons.image_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    skin.background,
                    skin.panel,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: skin.accent2.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule, color: skin.accent2, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_fmtTime(trip.ts),
                            style: TextStyle(
                                color: skin.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: scoreColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          score == null ? '评分 --' : '评分 $score · ${trip.scoreLabel}',
                          style: TextStyle(
                              color: scoreColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _hero(skin, trip.km.toStringAsFixed(1), 'km', '里程'),
                      _hero(skin, trip.avgSpeed.toStringAsFixed(0), 'km/h', '均速'),
                      _hero(skin, l100?.toStringAsFixed(1) ?? '--', 'L/100', '平均油耗'),
                    ],
                  ),
                  const Divider(height: 24, color: Colors.white12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.3,
                    children: [
                      _stat(skin, '最高车速', trip.maxSpeed.toStringAsFixed(0), 'km/h'),
                      _stat(skin, '消耗燃油', trip.fuel.toStringAsFixed(2), 'L'),
                      _stat(skin, '行驶用时', _fmtDuration(trip.sec), ''),
                      _stat(skin, '怠速占比',
                          trip.sec > 0
                              ? '${(trip.idleSec / trip.sec * 100).toStringAsFixed(0)}'
                              : '0',
                          '%'),
                      _stat(skin, '急加速', '${trip.harshAccel}', '次'),
                      _stat(skin, '急刹车', '${trip.harshBrake}', '次'),
                      if (trip.violations > 0)
                        _stat(skin, '超速提醒', '${trip.violations}', '次'),
                    ],
                  ),
                  Text('REV · 行车记录',
                      style: TextStyle(
                          color: skin.faint, fontSize: 10, letterSpacing: 1.2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (trip.track.length >= 2) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GPS 轨迹（${trip.track.length} 点 · 颜色=车速）',
                      style: TextStyle(color: skin.dim, fontSize: 12)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 180,
                    child: CustomPaint(
                      painter: _TrackPainter(track: trip.track, skin: skin),
                      size: Size.infinite,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '这段行程没有轨迹点。轨迹需要位置授权（隐私页「包含位置」）且定位可用；'
                '只在你同意的范围内记录，不上传、只存本机。',
                style: TextStyle(color: skin.faint, fontSize: 12, height: 1.5),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scoreColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.insights, color: scoreColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_advice(), style: TextStyle(color: scoreColor, fontSize: 13, height: 1.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _advice() {
    final s = trip.score;
    if (s == null) return '里程太短，评分不具参考性';
    if (s >= 90) return '节奏平稳、几乎无急加速急刹，继续保持';
    if (s >= 75) {
      return trip.harshBrake > trip.harshAccel
          ? '整体不错，急刹偏多（${trip.harshBrake} 次），跟车距离再留大一点'
          : '整体不错，可再减少几次急加速';
    }
    if (s >= 60) return '偏激烈：急加速 ${trip.harshAccel} 次 / 急刹 ${trip.harshBrake} 次，油耗和刹车都更费';
    return '很激烈的一段：急加速 ${trip.harshAccel} 次、急刹 ${trip.harshBrake} 次，建议放缓油门节奏';
  }

  Widget _hero(SkinDescriptor skin, String v, String unit, String label) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(v,
                style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 30,
                    color: skin.ink)),
            const SizedBox(width: 3),
            Text(unit, style: TextStyle(color: skin.dim, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: skin.dim, fontSize: 11)),
      ],
    );
  }

  Widget _stat(SkinDescriptor skin, String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: skin.faint, fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          fontFamily: 'DSEG7',
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: skin.ink)),
                ),
              ),
              if (unit.isNotEmpty)
                Text(' $unit', style: TextStyle(color: skin.faint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 轨迹折线：按车速着色（慢=青，快=橙红），并标出起终点。
class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.track, required this.skin});
  final List<List<double>> track;
  final SkinDescriptor skin;

  @override
  void paint(Canvas canvas, Size size) {
    if (track.length < 2) return;
    var minLat = track.first[0], maxLat = track.first[0];
    var minLng = track.first[1], maxLng = track.first[1];
    for (final p in track) {
      if (p[0] < minLat) minLat = p[0];
      if (p[0] > maxLat) maxLat = p[0];
      if (p[1] < minLng) minLng = p[1];
      if (p[1] > maxLng) maxLng = p[1];
    }
    // 纬度差换算成经度的等距比例，避免高纬度画出来横向拉伸。
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final scaleLat = latSpan < 1e-7 ? 1e-7 : latSpan;
    final scaleLng = lngSpan < 1e-7 ? 1e-7 : lngSpan;
    const pad = 12.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final speeds = track.map((p) => p.length > 2 ? p[2] : 0.0).toList();
    final maxV = speeds.reduce((a, b) => a > b ? a : b).clamp(10.0, 300.0);

    Offset at(List<double> p) => Offset(
          pad + (p[1] - minLng) / scaleLng * w,
          pad + (maxLat - p[0]) / scaleLat * h,
        );

    for (var i = 1; i < track.length; i++) {
      final v = speeds[i];
      final t = (v / maxV).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = Color.lerp(const Color(0xFF19E3FF), const Color(0xFFFF6B3D), t)!
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(at(track[i - 1]), at(track[i]), paint);
    }

    final startPaint = Paint()..color = const Color(0xFF41E39B);
    final endPaint = Paint()..color = const Color(0xFFFF6B3D);
    canvas.drawCircle(at(track.first), 4, startPaint);
    canvas.drawCircle(at(track.last), 4, endPaint);
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) =>
      old.track.length != track.length || old.track != track;
}
