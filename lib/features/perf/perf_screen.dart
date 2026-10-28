import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/perf/perf_timer.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/perf/horsepower_curve.dart';

class PerfScreen extends ConsumerStatefulWidget {
  const PerfScreen({super.key});

  @override
  ConsumerState<PerfScreen> createState() => _PerfScreenState();
}

class _PerfScreenState extends ConsumerState<PerfScreen> {
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    final s = t.perf;
    final skin = ref.watch(skinProvider);
    final isAccel = s.mode == 0;

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('性能测试'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('0-100 / 零四')),
              ButtonSegment(value: 1, label: Text('100-0 刹车')),
            ],
            selected: {s.mode},
            onSelectionChanged: (v) {
              t.setPerfMode(v.first);
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          // 演示模式：点开始后才跑一次受控场景（待命时不会自顾自计时）
          if (t.isOffline)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: s.state == PerfState.running
                  ? null
                  : () {
                      try {
                        t.startPerfScenario(s.mode);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('启动测试失败：$e')),
                          );
                        }
                      }
                    },
                icon: Icon(
                    s.state == PerfState.done ? Icons.replay : Icons.play_arrow,
                    size: 22),
                label: Text(
                  s.state == PerfState.running
                      ? '测试进行中…'
                      : s.state == PerfState.done
                          ? '重新测试'
                          : (s.mode == 0 ? '开始零百加速测试' : '开始刹车测试'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: skin.accent,
                  disabledBackgroundColor: skin.accent.withOpacity(0.35),
                ),
              ),
            )
          else
            // GPS / 真车：必须用户显式点"开始"才计时，点"结束"随时收尾。
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: s.state == PerfState.running
                      ? null
                      : () {
                          try {
                            t.beginPerfByUser(s.mode);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('启动测试失败：$e')),
                              );
                            }
                          }
                        },
                    icon: Icon(
                        s.state == PerfState.done
                            ? Icons.replay
                            : Icons.play_arrow,
                        size: 22),
                    label: Text(
                      s.state == PerfState.running
                          ? '计时中…'
                          : s.state == PerfState.done
                              ? '重新测试'
                              : (s.mode == 0
                                  ? (t.isGpsMode
                                      ? 'GPS 起步：点此开始 0-100'
                                      : '真车起步：点此开始 0-100')
                                  : (t.isGpsMode
                                      ? 'GPS 刹车：提速后点此开始'
                                      : '真车刹车：提速后点此开始')),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: skin.accent,
                      disabledBackgroundColor: skin.accent.withOpacity(0.35),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: s.state == PerfState.running
                      ? () {
                          try {
                            t.stopPerfByUser();
                          } catch (_) {}
                        }
                      : null,
                    icon: const Icon(Icons.stop, size: 20),
                    label: const Text('结束',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: const Color(0xFFFF5C7A),
                      side: const BorderSide(color: Color(0x66FF5C7A)),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          // 当前状态
          Center(
            child: Text(
              _stateText(s.state),
              style: TextStyle(
                color: skin.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isAccel) ...[
            _big('0-100 km/h', s.t100, 's', skin.accent),
            const SizedBox(height: 8),
            _big('0-400 m', s.t400, 's', skin.ink,
                tail: s.v400 != null ? '尾速 ${s.v400!.toStringAsFixed(0)} km/h' : null),
          ] else ...[
            _big('刹车用时', s.brakeT, 's', skin.bad),
            const SizedBox(height: 8),
            _big('刹车距离', s.brakeD, 'm', skin.ink, digits: 1),
          ],
          const SizedBox(height: 16),
          _dataRow('当前速度', '${t.current.speed.toStringAsFixed(0)} km/h'),
          _dataRow('峰值速度', '${s.peakSpeed.toStringAsFixed(0)} km/h'),
          _dataRow('已行驶', '${s.dist.toStringAsFixed(0)} m'),
          const SizedBox(height: 16),
          // 实时马力曲线
          HorsepowerCurve(
            data: t.current,
            accent: skin.accent,
            dim: skin.dim,
            faint: skin.faint,
          ),
          const Divider(height: 32),
          Text('历史最佳', style: TextStyle(color: skin.dim, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _bestRow('0-100', s.best100, 's'),
          _bestRow('0-400', s.best400, 's'),
          _bestRow('100-0 刹车', s.bestBrake, 's'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    try {
                      t.resetPerf();
                    } catch (_) {}
                    setState(() {});
                  },
                  child: const Text('重置'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            t.isOffline
                ? (isAccel
                    ? '演示模式：点击上方按钮后，车辆自动完成一次 0-100 与 0-400m 冲刺并记录成绩。'
                    : '演示模式：点击上方按钮后，车辆先加速到 100km/h 以上再全力刹停，自动记录用时与距离。')
                : t.isGpsMode
                    ? (isAccel
                        ? 'GPS 估算：车辆静止时点"开始"，系统按真实 GPS 速度积分 0-100 与 0-400m；未点开始绝不计时。'
                        : 'GPS 估算：提速到 100km/h 左右点"开始"，随后全力刹停，按真实速度/位移积分；可随时点"结束"。')
                    : (isAccel
                        ? '真车模式：静止时点"开始"，随后按真实车速积分 0-100 与 0-400m；未点开始绝不计时。'
                        : '真车模式：提速到 100km/h 左右点"开始"，随后全力刹停，按真实速度/位移积分。'),
            style: TextStyle(color: skin.faint, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  String _stateText(PerfState st) {
    switch (st) {
      case PerfState.idle:
        return '待命';
      case PerfState.running:
        return '计时中';
      case PerfState.done:
        return '完成';
    }
  }

  Widget _big(String label, double? v, String unit, Color color,
      {String? tail, int digits = 2}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                v == null ? '--.--' : v.toStringAsFixed(digits),
                style: TextStyle(
                  fontFamily: 'DSEG7',
                  fontWeight: FontWeight.bold,
                  fontSize: 40,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Text(unit, style: const TextStyle(color: Colors.white54, fontSize: 14)),
              if (tail != null) ...[
                const SizedBox(width: 12),
                Text(tail, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _bestRow(String label, double? v, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60)),
          Text(v == null ? '--' : '${v.toStringAsFixed(2)} $unit',
              style: const TextStyle(
                  color: Color(0xFFF2B23B), fontWeight: FontWeight.bold, fontFamily: 'DSEG7')),
        ],
      ),
    );
  }
}
