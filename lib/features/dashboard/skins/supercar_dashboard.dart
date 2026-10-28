import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// SUPERCAR · 超跑：顶部水平 RPM 条 + 巨型车速 + 底部六小表。
/// 移植原生 v1.9.6 的 drawSupercar。
class SupercarDashboard extends StatelessWidget {
  const SupercarDashboard({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });

  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  @override
  Widget build(BuildContext context) {
    return HorizonFxOverlay(
      accent: skin.accent,
      child: Container(
        decoration: BoxDecoration(color: skin.background),
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (orientation == Orientation.landscape) return _landscape();
            return _portrait();
          },
        ),
      ),
    );
  }

  // ── 横屏 ──
  Widget _landscape() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 顶部 RPM 条
          SizedBox(
            height: 28,
            child: _horizontalRpmBar(),
          ),
          // 中央：大车速 + 档位
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          data.speed.toStringAsFixed(0),
                          style: TextStyle(
                            fontFamily: 'DSEG7',
                            fontWeight: FontWeight.bold,
                            fontSize: 120,
                            color: skin.accent,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: skin.accent.withValues(alpha: 0.4),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text('KM/H',
                          style: TextStyle(
                              color: skin.dim,
                              fontSize: 14,
                              letterSpacing: 8)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GearWidget(
                          gear: data.gear,
                          fontSize: 60,
                          color: skin.accent),
                      const SizedBox(height: 6),
                      Text('GEAR',
                          style: TextStyle(
                              color: skin.faint,
                              fontSize: 12,
                              letterSpacing: 4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 底部六小表
          SizedBox(
            height: 80,
            child: _bottomGauges(),
          ),
        ],
      ),
    );
  }

  // ── 竖屏 ──
  Widget _portrait() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          SizedBox(height: 24, child: _horizontalRpmBar()),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    data.speed.toStringAsFixed(0),
                    style: TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 90,
                      color: skin.accent,
                      shadows: [
                        Shadow(
                          color: skin.accent.withValues(alpha: 0.4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                Text('KM/H',
                    style: TextStyle(
                        color: skin.dim, fontSize: 13, letterSpacing: 6)),
                const SizedBox(height: 20),
                GearWidget(
                    gear: data.gear,
                    fontSize: 48,
                    color: skin.accent),
                Text('GEAR',
                    style: TextStyle(
                        color: skin.faint, fontSize: 11, letterSpacing: 3)),
              ],
            ),
          ),
          Expanded(child: _portraitGauges()),
        ],
      ),
    );
  }

  // ── 水平 RPM 条（30段） ──
  Widget _horizontalRpmBar() {
    const seg = 30;
    const maxRpm = 8000;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(seg, (i) {
              final v = (i + 1) / seg * maxRpm;
              final active = data.rpm >= v;
              final inRed = v >= profile.redlineRpm;
              final col = active
                  ? (inRed ? skin.bad : skin.accent)
                  : (inRed
                      ? skin.accent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.08));
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < seg - 1 ? 2 : 0),
                  decoration: BoxDecoration(
                    color: col,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ── 底部六小表（横屏） ──
  Widget _bottomGauges() {
    final gauges = <_GaugeData>[
      _GaugeData('COOLANT', data.coolant?.toStringAsFixed(0), '°C',
          _coolColor(data.coolant)),
      _GaugeData('OIL TEMP', data.oilTemp?.toStringAsFixed(0), '°C',
          _tempColor(data.oilTemp)),
      _GaugeData('INTAKE', data.intakeTemp?.toStringAsFixed(0), '°C',
          _tempColor(data.intakeTemp)),
      _GaugeData('VOLTAGE', data.voltage?.toStringAsFixed(1), 'V',
          _voltColor(data.voltage)),
      _GaugeData('BOOST', data.boost?.toStringAsFixed(1), 'bar',
          skin.accent2),
      _GaugeData('LOAD', data.load?.toStringAsFixed(0), '%', skin.accent),
    ];
    final shown = data.isDemo
        ? gauges
        : gauges.where((e) => e.value != null).toList();

    return Row(
      children: shown.map((g) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(g.label,
                    style: TextStyle(
                        color: skin.dim, fontSize: 8, letterSpacing: 1)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(g.value ?? '--',
                          style: TextStyle(
                              fontFamily: 'DSEG7',
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: g.color)),
                      Text(g.unit,
                          style:
                              TextStyle(color: skin.faint, fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 竖屏数据 ──
  Widget _portraitGauges() {
    final gauges = <_GaugeData>[
      _GaugeData('水温', data.coolant?.toStringAsFixed(0), '°C',
          _coolColor(data.coolant)),
      _GaugeData('油温', data.oilTemp?.toStringAsFixed(0), '°C',
          _tempColor(data.oilTemp)),
      _GaugeData('电压', data.voltage?.toStringAsFixed(1), 'V',
          _voltColor(data.voltage)),
      _GaugeData('MAF', data.maf?.toStringAsFixed(1), 'g/s', skin.ink),
      _GaugeData('负荷', data.load?.toStringAsFixed(0), '%', skin.accent),
      _GaugeData('Boost', data.boost?.toStringAsFixed(1), 'bar',
          skin.accent2),
    ];
    final shown = data.isDemo
        ? gauges
        : gauges.where((e) => e.value != null).toList();

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final g = shown[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(g.label, style: TextStyle(color: skin.dim, fontSize: 12)),
              Row(
                children: [
                  Text(g.value ?? '--',
                      style: TextStyle(
                          fontFamily: 'DSEG7',
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: g.color)),
                  Text(g.unit,
                      style: TextStyle(color: skin.faint, fontSize: 9)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _coolColor(double? t) {
    if (t == null) return skin.faint;
    if (t >= profile.coolantDanger) return skin.bad;
    if (t >= profile.coolantWarn) return skin.warn;
    return skin.ink;
  }

  Color _tempColor(double? t) {
    if (t == null) return skin.faint;
    if (t > 105) return skin.bad;
    if (t > 95) return skin.warn;
    return skin.ink;
  }

  Color _voltColor(double? v) {
    if (v == null) return skin.faint;
    if (v < 12.5) return skin.bad;
    if (v > 14.6) return skin.warn;
    return skin.ink;
  }
}

class _GaugeData {
  _GaugeData(this.label, this.value, this.unit, this.color);
  final String label;
  final String? value;
  final String unit;
  final Color color;
}
