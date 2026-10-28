import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 全 PID 实时数据流：把当前帧支持的全部测量值逐行滚动刷新。
/// 真实模式下按 ECU 支持度隐藏 null 项；演示模式展示完整列表。
class DataStreamScreen extends ConsumerWidget {
  const DataStreamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(telemetryProvider);
    final d = t.current;
    final SkinDescriptor skin = ref.watch(skinProvider);

    final rows = _rowsOf(d);
    final shown = d.isDemo ? rows : rows.where((r) => r.value != null).toList();

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('实时数据流'),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (d.isDemo ? skin.warn : skin.ok).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: (d.isDemo ? skin.warn : skin.ok)
                      .withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.swap_vert,
                    size: 16,
                    color: d.isDemo ? skin.warn : skin.ok),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d.isDemo
                        ? '演示模式 · 模拟全量 PID（${rows.length} 项）'
                        : '本车支持 ${shown.length}/${rows.length} 项 PID，数据逐帧刷新',
                    style: TextStyle(
                        color: d.isDemo ? skin.warn : skin.ok, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              itemCount: shown.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1, color: Colors.white.withValues(alpha: 0.05)),
              itemBuilder: (context, i) => _streamRow(shown[i], skin),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streamRow(_StreamRow r, SkinDescriptor skin) {
    final has = r.value != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(r.label,
                style: TextStyle(color: skin.dim, fontSize: 13)),
          ),
          const Spacer(),
          Text(
            has ? r.value! : '--',
            style: TextStyle(
              fontFamily: 'DSEG7',
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: has ? skin.ink : skin.faint,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: Text(r.unit,
                textAlign: TextAlign.right,
                style: TextStyle(color: skin.faint, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  List<_StreamRow> _rowsOf(ObdData d) {
    return [
      _StreamRow('发动机转速', d.rpm.toString(), 'rpm'),
      _StreamRow('车速', d.speed.toStringAsFixed(0), 'km/h'),
      _StreamRow('档位', d.gear <= 0 ? 'N' : '${d.gear}', '挡'),
      _StreamRow('冷却液温度', d.coolant?.toStringAsFixed(0), '°C'),
      _StreamRow('机油温度', d.oilTemp?.toStringAsFixed(0), '°C'),
      _StreamRow('进气温度', d.intakeTemp?.toStringAsFixed(0), '°C'),
      _StreamRow('环境温度', d.ambient?.toStringAsFixed(0), '°C'),
      _StreamRow('电瓶电压', d.voltage?.toStringAsFixed(2), 'V'),
      _StreamRow('进气歧管压力', d.map?.toStringAsFixed(0), 'kPa'),
      _StreamRow('增压压力', d.boost?.toStringAsFixed(2), 'bar'),
      _StreamRow('空气流量 MAF', d.maf?.toStringAsFixed(1), 'g/s'),
      _StreamRow('发动机负荷', d.load?.toStringAsFixed(0), '%'),
      _StreamRow('绝对负荷', d.absLoad?.toStringAsFixed(0), '%'),
      _StreamRow('节气门开度', d.throttle?.toStringAsFixed(0), '%'),
      _StreamRow('点火提前角', d.ignAdv?.toStringAsFixed(1), '°'),
      _StreamRow('长期燃油修正', d.ltft?.toStringAsFixed(1), '%'),
      _StreamRow('燃油液位', d.fuelLevel?.toStringAsFixed(0), '%'),
      _StreamRow('瞬时油耗', d.fuelL100?.toStringAsFixed(1), 'L/100'),
      _StreamRow('小时油耗', d.fuelLph?.toStringAsFixed(2), 'L/h'),
      _StreamRow('燃油轨压力', d.fuelRailP?.toStringAsFixed(3), 'MPa'),
      _StreamRow('催化器温度', d.catTemp?.toStringAsFixed(0), '°C'),
      _StreamRow('变速箱油温', d.atfTemp?.toStringAsFixed(0), '°C'),
      _StreamRow('扭矩请求', d.torque?.toStringAsFixed(0), 'Nm'),
      _StreamRow('海拔(反算)', d.altitude?.toStringAsFixed(0), 'm'),
      _StreamRow('行程里程', d.tripKm.toStringAsFixed(1), 'km'),
      _StreamRow('行程耗油', d.tripFuel.toStringAsFixed(2), 'L'),
      _StreamRow('行程用时', _fmtSec(d.tripSec), ''),
      _StreamRow('行程平均油耗', d.tripL100?.toStringAsFixed(1), 'L/100'),
      _StreamRow('行程平均车速', d.tripAvgSpeed.toStringAsFixed(0), 'km/h'),
    ];
  }

  static String _fmtSec(double sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = (sec % 60).round();
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _StreamRow {
  const _StreamRow(this.label, this.value, this.unit);
  final String label;
  final String? value;
  final String unit;
}
