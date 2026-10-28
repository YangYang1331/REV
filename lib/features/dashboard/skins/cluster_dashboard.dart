import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/circular_gauge.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// CLUSTER · 赛车橙：圆形转速表 + 中央大车速/档位 + 右侧数据流。
/// 移植原生 v1.9.6 的 drawLandscape / drawPortrait。
class ClusterDashboard extends StatelessWidget {
  const ClusterDashboard({
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
            if (orientation == Orientation.landscape) {
              return _landscape();
            }
            return _portrait();
          },
        ),
      ),
    );
  }

  // ── 横屏：左圆表 / 中车速 / 右数据流 ──
  Widget _landscape() {
    return Row(
      children: [
        // 左：圆形转速表
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: CircularRpmGauge(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                maxRpm: 8000,
                accent: skin.accent,
                bad: skin.bad,
                dim: skin.dim,
                ink: skin.ink,
                faint: skin.faint,
                fontFamily: 'UI',
              ),
            ),
          ),
        ),
        Container(
          width: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        // 中：大车速 + 档位
        Expanded(
          flex: 4,
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
                    fontSize: 110,
                    color: skin.accent,
                    height: 1.0,
                    shadows: [
                      Shadow(
                        color: skin.accent.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'KM/H',
                style: TextStyle(
                  color: skin.dim,
                  fontSize: 13,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GearWidget(
                      gear: data.gear,
                      fontSize: 42,
                      color: skin.accent),
                  const SizedBox(width: 12),
                  Text(
                    'GEAR',
                    style: TextStyle(
                      color: skin.faint,
                      fontSize: 11,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _tripInfo(),
            ],
          ),
        ),
        Container(
          width: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        // 右：数据流
        Expanded(
          flex: 3,
          child: _streamList(),
        ),
      ],
    );
  }

  // ── 竖屏：上圆表 / 中车速 / 下数据 ──
  Widget _portrait() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: CircularRpmGauge(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                maxRpm: 8000,
                accent: skin.accent,
                bad: skin.bad,
                dim: skin.dim,
                ink: skin.ink,
                faint: skin.faint,
                fontFamily: 'UI',
              ),
            ),
          ),
        ),
        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        Expanded(
          flex: 2,
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
                    fontSize: 80,
                    color: skin.accent,
                    shadows: [
                      Shadow(
                        color: skin.accent.withValues(alpha: 0.4),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
              Text('KM/H',
                  style: TextStyle(
                      color: skin.dim, fontSize: 12, letterSpacing: 5)),
              const SizedBox(height: 12),
              GearWidget(
                  gear: data.gear,
                  fontSize: 36,
                  color: skin.accent),
            ],
          ),
        ),
        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        Expanded(
          flex: 2,
          child: _streamGrid(),
        ),
      ],
    );
  }

  // ── 行程信息 ──
  Widget _tripInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _miniStat('TRIP', '${data.tripKm.toStringAsFixed(1)} km'),
        const SizedBox(width: 24),
        _miniStat('TIME', _fmtTime(data.tripSec)),
      ],
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: skin.faint, fontSize: 9, letterSpacing: 2)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(color: skin.ink, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ── 右侧数据流（横屏） ──
  Widget _streamList() {
    final items = <_StreamItem>[
      _StreamItem('COOLANT', data.coolant?.toStringAsFixed(0), '°C',
          _coolColor(data.coolant)),
      _StreamItem('OIL TEMP', data.oilTemp?.toStringAsFixed(0), '°C',
          _tempColor(data.oilTemp)),
      _StreamItem('INTAKE', data.intakeTemp?.toStringAsFixed(0), '°C',
          _tempColor(data.intakeTemp)),
      _StreamItem('VOLTAGE', data.voltage?.toStringAsFixed(1), 'V',
          _voltColor(data.voltage)),
      _StreamItem('BOOST', data.boost?.toStringAsFixed(1), 'bar',
          skin.accent2),
      _StreamItem('LOAD', data.load?.toStringAsFixed(0), '%', skin.ink),
      _StreamItem('MAF', data.maf?.toStringAsFixed(1), 'g/s', skin.ink),
      _StreamItem('FUEL', data.fuelLevel?.toStringAsFixed(0), '%', skin.ink),
    ];

    final shown = data.showUnsupportedAsDashes ? items : items.where((e) => e.value != null).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final e = shown[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Text(e.label,
                  style: TextStyle(
                      color: skin.dim, fontSize: 10, letterSpacing: 1.5)),
              const Spacer(),
              Text(
                e.value ?? '--',
                style: TextStyle(
                  fontFamily: 'DSEG7',
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: e.color,
                ),
              ),
              const SizedBox(width: 4),
              Text(e.unit,
                  style: TextStyle(color: skin.faint, fontSize: 9)),
            ],
          ),
        );
      },
    );
  }

  // ── 竖屏数据流网格 ──
  Widget _streamGrid() {
    final items = <_StreamItem>[
      _StreamItem('水温', data.coolant?.toStringAsFixed(0), '°C',
          _coolColor(data.coolant)),
      _StreamItem('电压', data.voltage?.toStringAsFixed(1), 'V',
          _voltColor(data.voltage)),
      _StreamItem('MAF', data.maf?.toStringAsFixed(1), 'g/s', skin.ink),
      _StreamItem('负荷', data.load?.toStringAsFixed(0), '%', skin.ink),
    ];
    final shown = data.showUnsupportedAsDashes ? items : items.where((e) => e.value != null).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final e = shown[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.label, style: TextStyle(color: skin.dim, fontSize: 11)),
              Row(
                children: [
                  Text(e.value ?? '--',
                      style: TextStyle(
                          fontFamily: 'DSEG7',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: e.color)),
                  Text(e.unit,
                      style: TextStyle(color: skin.faint, fontSize: 9)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 颜色判断 ──
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

  String _fmtTime(double sec) {
    final s = sec.toInt();
    final hh = s ~/ 3600;
    final mm = (s % 3600) ~/ 60;
    final ss = s % 60;
    if (hh > 0) return '$hh:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }
}

class _StreamItem {
  _StreamItem(this.label, this.value, this.unit, this.color);
  final String label;
  final String? value;
  final String unit;
  final Color color;
}
