import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 电池健康检测：启动压降 + 充电电压 + 电压历史。
class BatteryHealthScreen extends ConsumerStatefulWidget {
  const BatteryHealthScreen({super.key});

  @override
  ConsumerState<BatteryHealthScreen> createState() =>
      _BatteryHealthScreenState();
}

class _BatteryHealthScreenState extends ConsumerState<BatteryHealthScreen> {
  // 电压历史（最近 150 个样本）
  final List<double> _vHistory = [];
  // 启动压降检测
  bool _wasCranking = false;
  double? _crankMin;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    final d = t.current;
    final skin = ref.watch(skinProvider);

    // 记录电压历史
    final v = d.voltage;
    if (v != null) {
      _detectCranking(d, v);
      _vHistory.add(v);
      if (_vHistory.length > 150) _vHistory.removeAt(0);
    }

    // 电池健康等级
    final health = _batteryHealth();
    final charge = _chargeStatus(d, v);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('电池健康检测'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 电池健康总览
          _healthCard(health, skin),
          const SizedBox(height: 14),
          // 启动压降
          _crankCard(skin),
          const SizedBox(height: 14),
          // 充电系统
          _chargeCard(charge, v, skin),
          const SizedBox(height: 14),
          // 电压历史曲线
          _historyCard(skin),
          const SizedBox(height: 16),
          Text(
            '检测原理：启动发动机时电瓶需带动起动机，电压会短暂跌落，'
            '跌得越深说明电瓶储电能力越差；怠速时发电机应将电压维持在 13.5-14.5V。',
            style: TextStyle(color: skin.faint, fontSize: 11, height: 1.7),
          ),
        ],
      ),
    );
  }

  /// 检测启动压降：电压跌破 12V 且转速低（起动机带动）时记录。
  void _detectCranking(ObdData d, double v) {
    final cranking = v < 12.0 && d.rpm < 1500;
    if (cranking) {
      _wasCranking = true;
      if (_crankMin == null || v < _crankMin!) _crankMin = v;
    } else if (_wasCranking && d.rpm > 1500) {
      // 已启动完成，保留 _crankMin
      _wasCranking = false;
    }
  }

  /// 电池健康等级（基于启动压降）。
  _Health _batteryHealth() {
    final min = _crankMin;
    if (min == null) return _Health.unknown;
    if (min >= 10.5) return _Health.good;
    if (min >= 9.5) return _Health.fair;
    return _Health.replace;
  }

  /// 充电系统状态。
  _Charge _chargeStatus(ObdData d, double? v) {
    if (v == null || d.rpm < 1500) return _Charge.idle;
    if (v >= 13.5 && v <= 14.5) return _Charge.normal;
    if (v > 14.8) return _Charge.overcharge;
    return _Charge.low;
  }

  Widget _healthCard(_Health health, skin) {
    final (icon, title, color, desc) = switch (health) {
      _Health.good => (
          Icons.battery_full,
          '状态良好',
          skin.ok,
          '启动有力，储电能力正常'
        ),
      _Health.fair => (
          Icons.battery_3_bar,
          '状态一般',
          skin.warn,
          '电瓶开始老化，建议留意'
        ),
      _Health.replace => (
          Icons.battery_alert,
          '需要更换',
          skin.bad,
          '启动压降过大，建议尽快更换电瓶'
        ),
      _Health.unknown => (
          Icons.battery_unknown,
          '尚未检测',
          skin.dim,
          '启动一次发动机后自动评估'
        ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 34, color: color),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(color: skin.dim, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _crankCard(skin) {
    return _infoCard(
      '启动压降',
      _crankMin == null ? '--' : _crankMin!.toStringAsFixed(1),
      'V',
      _crankMin == null
          ? skin.dim
          : _crankMin! >= 10.5
              ? skin.ok
              : _crankMin! >= 9.5
                  ? skin.warn
                  : skin.bad,
      '正常应 ≥ 10.5V',
      skin,
    );
  }

  Widget _chargeCard(_Charge charge, double? v, skin) {
    final (title, color) = switch (charge) {
      _Charge.normal => ('充电正常', skin.ok),
      _Charge.low => ('充电不足', skin.bad),
      _Charge.overcharge => ('过充', skin.warn),
      _Charge.idle => ('未在充电', skin.dim),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.electrical_services, color: color, size: 28),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text('怠速时应维持 13.5-14.5V',
                  style: TextStyle(color: skin.faint, fontSize: 11)),
            ],
          ),
          const Spacer(),
          if (v != null)
            Text(v.toStringAsFixed(1),
                style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 30,
                    color: color)),
        ],
      ),
    );
  }

  Widget _historyCard(skin) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('电压历史',
              style: TextStyle(
                  color: skin.dim, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: CustomPaint(
              size: Size.infinite,
              painter: _VoltPainter(
                history: _vHistory,
                accent: skin.accent,
                faint: skin.faint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
      String label, String value, String unit, Color color, String hint, skin) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: skin.dim, fontSize: 14, fontWeight: FontWeight.w600)),
              Text(hint, style: TextStyle(color: skin.faint, fontSize: 11)),
            ],
          ),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontFamily: 'DSEG7',
                  fontWeight: FontWeight.bold,
                  fontSize: 34,
                  color: color)),
          const SizedBox(width: 4),
          Text(unit, style: TextStyle(color: skin.dim, fontSize: 13)),
        ],
      ),
    );
  }
}

enum _Health { good, fair, replace, unknown }
enum _Charge { normal, low, overcharge, idle }

class _VoltPainter extends CustomPainter {
  _VoltPainter({
    required this.history,
    required this.accent,
    required this.faint,
  });

  final List<double> history;
  final Color accent;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    const minV = 9.0, maxV = 15.0;

    // 参考线（13.5 / 14.5）
    for (final ref in [13.5, 14.5]) {
      final y = size.height - (ref - minV) / (maxV - minV) * size.height;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = faint.withValues(alpha: 0.25)
          ..strokeWidth = 0.5,
      );
    }

    final path = Path();
    for (var i = 0; i < history.length; i++) {
      final x = size.width * i / 149;
      final y = size.height -
          (history[i] - minV) / (maxV - minV) * size.height;
      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _VoltPainter old) =>
      old.history != history;
}
