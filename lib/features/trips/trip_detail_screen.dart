import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';

/// 单次行程详情：时间 / 里程 / 油耗 / 平均油耗 / 平均车速 / 用时。
class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.trip});

  final TripRec trip;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(skinProvider);
    final l100 = trip.l100;

    // 2.0L 自吸参考：<8 优秀，8–11 正常，>11 偏高
    final (effColor, effLabel) = l100 == null
        ? (skin.dim, '里程过短，油耗不具参考性')
        : l100 < 8
            ? (skin.ok, '油耗表现优秀')
            : l100 <= 11
                ? (skin.warn, '油耗适中')
                : (skin.bad, '油耗偏高，注意驾驶习惯');

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('行程详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: skin.accent2.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: skin.accent2.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: skin.accent2, size: 22),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('开始时间',
                        style: TextStyle(color: skin.dim, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(_fmtTime(trip.ts),
                        style: TextStyle(
                            color: skin.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: [
              _stat(skin, '行驶里程', trip.km.toStringAsFixed(1), 'km'),
              _stat(skin, '消耗燃油', trip.fuel.toStringAsFixed(2), 'L'),
              _stat(skin, '平均油耗', l100?.toStringAsFixed(1) ?? '--', 'L/100km'),
              _stat(skin, '平均车速', trip.avgSpeed.toStringAsFixed(0), 'km/h'),
              _stat(skin, '行驶用时', _fmtDuration(trip.sec), ''),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: effColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: effColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.eco, color: effColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(effLabel,
                      style: TextStyle(
                          color: effColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
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
                          fontSize: 24,
                          color: skin.ink)),
                ),
              ),
              if (unit.isNotEmpty)
                Text(' $unit',
                    style: TextStyle(color: skin.faint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
