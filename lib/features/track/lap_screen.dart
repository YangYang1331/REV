import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/track/lap_timer.dart';

/// 圈速计时页面：手动开始/结束圈，最佳圈速，预测差值。
class LapScreen extends ConsumerStatefulWidget {
  const LapScreen({super.key});

  @override
  ConsumerState<LapScreen> createState() => _LapScreenState();
}

class _LapScreenState extends ConsumerState<LapScreen> {
  final LapTimer _lap = LapTimer();

  @override
  void dispose() {
    _lap.dispose();
    super.dispose();
  }

  void _toggleLap() {
    if (_lap.isRunning) {
      _lap.endLap();
    } else {
      _lap.start();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final running = _lap.isRunning;
    final delta = _lap.predictedDelta;
    final predState = _lap.predictionState;

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('圈速计时'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: running ? null : () => setState(() => _lap.reset()),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // 圈数
          Text('LAP ${_lap.lapCount.toString().padLeft(2, '0')}',
              style: TextStyle(
                  color: skin.dim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          // 当前圈大时间
          Expanded(
            flex: 3,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    formatLapTime(_lap.currentLap),
                    style: TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 72,
                      color: running ? skin.ink : skin.dim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 预测差值
                  if (running && delta != null)
                    _deltaBadge(delta, predState, skin)
                  else
                    Text(running ? '计时中…' : '准备开始',
                        style: TextStyle(
                            color: skin.faint,
                            fontSize: 13)),
                ],
              ),
            ),
          ),
          // 开始/结束大按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _toggleLap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 64,
                  decoration: BoxDecoration(
                    color: running ? skin.bad : skin.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(running ? Icons.stop : Icons.flag,
                          color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        running ? '结束本圈' : '开始一圈',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 最佳 / 上一圈
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          '最佳圈速',
                          _lap.bestLap == null
                              ? '--:--.-'
                              : formatLapTime(_lap.bestLap!),
                          skin.ok,
                          skin,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          '上一圈',
                          _lap.lastLap == null
                              ? '--:--.-'
                              : formatLapTime(_lap.lastLap!),
                          skin.ink,
                          skin,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 历史圈速
                  Expanded(
                    child: _lap.lapHistory.isEmpty
                        ? Center(
                            child: Text('暂无圈速记录',
                                style: TextStyle(
                                    color: skin.faint, fontSize: 12)),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _lap.lapHistory.length,
                            itemBuilder: (context, i) {
                              final t = _lap.lapHistory[i];
                              final isBest = t == _lap.bestLap;
                              return Container(
                                width: 90,
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: isBest
                                      ? skin.ok.withValues(alpha: 0.1)
                                      : Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isBest
                                        ? skin.ok.withValues(alpha: 0.4)
                                        : Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('LAP ${i + 1}',
                                        style: TextStyle(
                                            color: skin.faint,
                                            fontSize: 9,
                                            letterSpacing: 1)),
                                    const SizedBox(height: 4),
                                    Text(formatLapTime(t),
                                        style: TextStyle(
                                          fontFamily: 'DSEG7',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isBest
                                              ? skin.ok
                                              : skin.ink,
                                        )),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _deltaBadge(double delta, int? state, skin) {
    final faster = (state ?? 0) < 0;
    final color = faster ? skin.ok : skin.bad;
    final sign = delta > 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(faster ? Icons.trending_down : Icons.trending_up,
              size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$sign${delta.toStringAsFixed(1)}s ${faster ? '更快' : '更慢'}',
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, skin) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: skin.dim, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                fontFamily: 'DSEG7',
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: color,
              )),
        ],
      ),
    );
  }
}
