import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 车辆健康报告：一页汇总电池 / 发动机温度 / 故障码 / 本次行程，
/// 顶部给出 100 分制总体评分，按告警项扣分。
class HealthReportScreen extends ConsumerWidget {
  const HealthReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(telemetryProvider);
    final ObdData d = t.current;
    final SkinDescriptor skin = ref.watch(skinProvider);

    final battery = _assessBattery(d);
    final thermal = _assessThermal(d);
    final codes = d.isDemo ? DtcDatabase.demoCodes : const <String>[];
    final dtc = _assessDtc(codes);

    var score = 100;
    score += battery.deduct;
    score += thermal.deduct;
    score += dtc.deduct;
    score = score.clamp(0, 100);
    final verdict = score >= 90
        ? _Verdict.good
        : score >= 70
            ? _Verdict.warn
            : _Verdict.bad;

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('健康报告'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _scoreCard(score, verdict, skin, d.isDemo),
          const SizedBox(height: 14),
          _sectionCard(
            skin,
            icon: Icons.battery_charging_full,
            title: '电池 / 充电系统',
            status: battery.status,
            lines: battery.lines,
          ),
          const SizedBox(height: 12),
          _sectionCard(
            skin,
            icon: Icons.thermostat,
            title: '发动机温度',
            status: thermal.status,
            lines: thermal.lines,
          ),
          const SizedBox(height: 12),
          _sectionCard(
            skin,
            icon: Icons.error_outline,
            title: '故障码（DTC）',
            status: dtc.status,
            lines: [
              '检测到 ${codes.length} 个故障码',
              ...codes.map((c) {
                final info = DtcDatabase.lookup(c);
                return '$c${info == null ? '' : ' · ${info.title}'}';
              }),
            ],
          ),
          const SizedBox(height: 12),
          _tripCard(d, skin),
          const SizedBox(height: 16),
          Text(
            '评分规则：满分 100，充电异常、水温过高、存在故障码等按严重程度扣分；'
            '演示模式数据为模拟值，仅供参考。',
            style: TextStyle(color: skin.faint, fontSize: 11, height: 1.7),
          ),
        ],
      ),
    );
  }

  // ── 总体评分 ──
  Widget _scoreCard(int score, _Verdict v, SkinDescriptor skin, bool demo) {
    final (color, label) = switch (v) {
      _Verdict.good => (skin.ok, '状态良好'),
      _Verdict.warn => (skin.warn, '需要留意'),
      _Verdict.bad => (skin.bad, '建议检修'),
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('总体健康评分',
                  style: TextStyle(
                      color: skin.dim, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$score',
                      style: TextStyle(
                        fontFamily: 'DSEG7',
                        fontWeight: FontWeight.bold,
                        fontSize: 48,
                        color: color,
                      )),
                  Text(' /100',
                      style: TextStyle(color: skin.faint, fontSize: 13)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.favorite, color: color, size: 30),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (demo)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: skin.warn.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('DEMO 演示数据',
                      style: TextStyle(
                          color: skin.warn,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 分项卡片 ──
  Widget _sectionCard(
    SkinDescriptor skin, {
    required IconData icon,
    required String title,
    required _Status status,
    required List<String> lines,
  }) {
    final color = switch (status) {
      _Status.ok => skin.ok,
      _Status.warn => skin.warn,
      _Status.bad => skin.bad,
      _Status.unknown => skin.dim,
    };
    final tag = switch (status) {
      _Status.ok => '正常',
      _Status.warn => '偏高',
      _Status.bad => '异常',
      _Status.unknown => '无数据',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: skin.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(tag,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Text(l,
                    style: TextStyle(color: skin.dim, fontSize: 12.5, height: 1.5)),
              )),
        ],
      ),
    );
  }

  // ── 本次行程汇总 ──
  Widget _tripCard(ObdData d, SkinDescriptor skin) {
    final l100 = d.tripL100;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, size: 20, color: skin.accent2),
              const SizedBox(width: 10),
              Text('本次行程汇总',
                  style: TextStyle(
                      color: skin.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _tripStat(d.tripKm.toStringAsFixed(1), 'km', '里程', skin),
              _tripStat(d.tripFuel.toStringAsFixed(2), 'L', '耗油', skin),
              _tripStat(l100?.toStringAsFixed(1) ?? '--', 'L/100', '平均油耗', skin),
              _tripStat(
                  d.tripAvgSpeed.toStringAsFixed(0), 'km/h', '平均车速', skin),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tripStat(String v, String unit, String label, SkinDescriptor skin) {
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
                    fontSize: 22,
                    color: skin.ink)),
            const SizedBox(width: 3),
            Text(unit, style: TextStyle(color: skin.faint, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: skin.faint, fontSize: 11)),
      ],
    );
  }

  // ── 评估逻辑 ──
  _ReportItem _assessBattery(ObdData d) {
    final v = d.voltage;
    if (v == null) {
      return const _ReportItem(_Status.unknown, -0, [
        '未读到电瓶电压，连接 ELM327 后自动评估',
      ]);
    }
    final running = d.rpm >= 1500;
    if (running) {
      if (v >= 13.5 && v <= 14.5) {
        return _ReportItem(_Status.ok, 0, [
          '当前电压 ${v.toStringAsFixed(2)}V，发电机充电正常（13.5–14.5V）',
        ]);
      }
      if (v > 14.8) {
        return _ReportItem(_Status.bad, -15, [
          '当前电压 ${v.toStringAsFixed(2)}V，偏高：可能过充，检查发电机调节器',
        ]);
      }
      return _ReportItem(_Status.warn, -8, [
        '当前电压 ${v.toStringAsFixed(2)}V，充电不足：检查发电机皮带 / 电瓶老化',
      ]);
    }
    if (v < 11.8) {
      return _ReportItem(_Status.warn, -10, [
        '当前电压 ${v.toStringAsFixed(2)}V，怠速/熄火状态偏低，留意电瓶储电能力',
      ]);
    }
    return _ReportItem(_Status.ok, 0, [
      '当前电压 ${v.toStringAsFixed(2)}V，静态电压正常（≥12V 为健康电瓶）',
    ]);
  }

  _ReportItem _assessThermal(ObdData d) {
    final c = d.coolant;
    final lines = <String>[];
    var status = _Status.unknown;
    var deduct = 0;
    if (c == null) {
      lines.add('未读到水温数据');
    } else if (c >= 110) {
      status = _Status.bad;
      deduct = -20;
      lines.add('水温 ${c.toStringAsFixed(0)}°C 过高！立即安全停车怠速降温，勿立即熄火');
    } else if (c >= 102) {
      status = _Status.warn;
      deduct = -8;
      lines.add('水温 ${c.toStringAsFixed(0)}°C 偏高，检查冷却液液位与节温器');
    } else if (c < 60 && d.rpm > 1000) {
      status = _Status.warn;
      deduct = -3;
      lines.add('水温 ${c.toStringAsFixed(0)}°C 偏低，节温器可能常开，热车前避免大脚油门');
    } else {
      status = _Status.ok;
      lines.add('水温 ${c.toStringAsFixed(0)}°C，工作温度正常（70–105°C）');
    }
    final it = d.intakeTemp;
    if (it != null) {
      lines.add(it > 55
          ? '进气温度 ${it.toStringAsFixed(0)}°C 偏高，动力会受限'
          : '进气温度 ${it.toStringAsFixed(0)}°C 正常');
    }
    return _ReportItem(status, deduct, lines);
  }

  _ReportItem _assessDtc(List<String> codes) {
    if (codes.isEmpty) {
      return const _ReportItem(_Status.ok, 0, ['未检测到故障码，ECU 状态良好']);
    }
    return _ReportItem(
        codes.length > 2 ? _Status.bad : _Status.warn,
        -12 * codes.length,
        ['检测到 ${codes.length} 个故障码，建议尽快读取详情并检修']);
  }
}

enum _Status { ok, warn, bad, unknown }

enum _Verdict { good, warn, bad }

class _ReportItem {
  const _ReportItem(this.status, this.deduct, this.lines);
  final _Status status;
  final int deduct;
  final List<String> lines;
}
