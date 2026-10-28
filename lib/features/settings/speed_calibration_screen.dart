import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/data/obd_providers.dart';

/// 速度校准：用乘数修正 OBD 车速与实际偏差。
class SpeedCalibrationScreen extends ConsumerStatefulWidget {
  const SpeedCalibrationScreen({super.key});

  @override
  ConsumerState<SpeedCalibrationScreen> createState() =>
      _SpeedCalibrationScreenState();
}

class _SpeedCalibrationScreenState
    extends ConsumerState<SpeedCalibrationScreen> {
  double _factor = 1.0;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    if (!_loaded) {
      _factor = t.speedFactor;
      _loaded = true;
    }
    final demo = t.current.speed;
    return Scaffold(
      appBar: AppBar(title: const Text('速度校准')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('校准系数：${_factor.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              '当 OBD 显示车速与实际不符时调整：显示偏快 5% 设为 0.95，偏慢 5% 设为 1.05。',
              style: TextStyle(color: Colors.white54, height: 1.6),
            ),
            const SizedBox(height: 20),
            Slider(
              value: _factor.clamp(0.5, 1.5),
              min: 0.5,
              max: 1.5,
              divisions: 100,
              label: _factor.toStringAsFixed(2),
              onChanged: (v) => setState(() => _factor = v),
              onChangeEnd: (v) => t.setSpeedFactor(v),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('显示车速', style: TextStyle(color: Colors.white70)),
                  Text(
                    '${(demo * _factor).toStringAsFixed(0)} km/h',
                    style: const TextStyle(
                        fontFamily: 'DSEG7',
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                        color: Color(0xFF27D6E6)),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() => _factor = 1.0);
                      t.setSpeedFactor(1.0);
                    },
                    child: const Text('恢复默认 1.00'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      t.setSpeedFactor(_factor);
                      Navigator.pop(context);
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
