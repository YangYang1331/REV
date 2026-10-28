import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/hex_dot.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// AMBER_GT · 金瞳琥珀：J 形垂直转速条 + 点阵档位 + GT 徽章 + 车标。
/// 移植原生 v1.9.6 的 drawAmberGt。
class AmberGtDashboard extends StatelessWidget {
  const AmberGtDashboard({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });

  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  String get _gear {
    if (data.gear < 0) return '-';
    if (data.gear == 0) return 'N';
    return data.gear.toString();
  }

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

  // ── 竖屏：左 GT徽章/档位/车速，中 J形转速条，右温度数据 ──
  Widget _portrait() {
    return Row(
      children: [
        // 左：GT 徽章 + 档位 + 车速
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _gtBadge(),
              Column(
                children: [
                  Text('GEAR',
                      style: TextStyle(
                          color: skin.accent,
                          fontSize: 10,
                          letterSpacing: 2)),
                  const SizedBox(height: 6),
                  DotGear(gear: _gear, color: skin.accent2, size: 42),
                ],
              ),
              Column(
                children: [
                  Text('KM/H',
                      style: TextStyle(
                          color: skin.accent,
                          fontSize: 10,
                          letterSpacing: 2)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      data.speed.toStringAsFixed(0),
                      style: TextStyle(
                        fontFamily: 'DSEG7',
                        fontWeight: FontWeight.bold,
                        fontSize: 36,
                        color: skin.accent2,
                        shadows: [
                          Shadow(
                            color: skin.accent.withValues(alpha: 0.6),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 中：J 形垂直转速条
        Expanded(
          flex: 2,
          child: _jRpmBar(),
        ),
        // 右：水温/进气/增压
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 竖屏侧栏温度单位补全（原版误传 '°'，缺 C）。
              _sideData('COOL', data.coolant?.toStringAsFixed(0), '°C',
                  _coolColor(data.coolant)),
              _sideData('INTAKE', data.intakeTemp?.toStringAsFixed(0), '°C',
                  _tempColor(data.intakeTemp)),
              _sideData('BOOST', data.boost?.toStringAsFixed(1), 'bar',
                  skin.accent),
              _sideData('VOLT', data.voltage?.toStringAsFixed(1), 'V',
                  _voltColor(data.voltage)),
            ],
          ),
        ),
      ],
    );
  }

  // ── 横屏：左档位/车速，中转速条，右数据 ──
  Widget _landscape() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _gtBadge(),
              const SizedBox(height: 16),
              DotGear(gear: _gear, color: skin.accent2, size: 48),
              const SizedBox(height: 8),
              Text('GEAR',
                  style: TextStyle(
                      color: skin.accent, fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 20),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  data.speed.toStringAsFixed(0),
                  style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 60,
                    color: skin.accent2,
                    shadows: [
                      Shadow(
                        color: skin.accent.withValues(alpha: 0.6),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
              Text('KM/H',
                  style: TextStyle(
                      color: skin.accent, fontSize: 10, letterSpacing: 3)),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: _jRpmBar(),
        ),
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _sideData('COOLANT', data.coolant?.toStringAsFixed(0), '°C',
                  _coolColor(data.coolant)),
              _sideData('OIL TEMP', data.oilTemp?.toStringAsFixed(0), '°C',
                  _tempColor(data.oilTemp)),
              _sideData('INTAKE', data.intakeTemp?.toStringAsFixed(0), '°C',
                  _tempColor(data.intakeTemp)),
              _sideData('VOLTAGE', data.voltage?.toStringAsFixed(1), 'V',
                  _voltColor(data.voltage)),
              _sideData('BOOST', data.boost?.toStringAsFixed(1), 'bar',
                  skin.accent),
              _sideData('LOAD', data.load?.toStringAsFixed(0), '%',
                  skin.accent2),
            ],
          ),
        ),
      ],
    );
  }

  // ── GT 徽章 ──
  Widget _gtBadge() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: skin.accent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: skin.accent.withValues(alpha: 0.4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'GT',
          style: TextStyle(
            fontFamily: 'DSEG7',
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: skin.accent,
          ),
        ),
      ),
    );
  }

  // ── J 形垂直转速条（带钩） ──
  Widget _jRpmBar() {
    const seg = 26;
    const maxRpm = 8000;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text('RPM',
              style: TextStyle(
                  color: skin.accent, fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 条段（固定宽度）
                SizedBox(
                  width: 16,
                  child: Column(
                    children: List.generate(seg, (i) {
                      final v = (seg - i) / seg * maxRpm;
                      final active = data.rpm >= v;
                      final inRed = v >= profile.redlineRpm;
                      final col = active
                          ? (inRed ? skin.bad : skin.accent2)
                          : (inRed
                              ? skin.bad.withValues(alpha: 0.15)
                              : skin.accent.withValues(alpha: 0.12));
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 4),
                // 刻度数字
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('8', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('6', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('4', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('2', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('0', style: TextStyle(color: skin.dim, fontSize: 8)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 右侧数据 ──
  Widget _sideData(String label, String? value, String unit, Color color) {
    if (!data.showUnsupportedAsDashes && value == null) return const SizedBox.shrink();
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: skin.accent, fontSize: 9, letterSpacing: 1.5)),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value ?? '--',
              style: TextStyle(
                fontFamily: 'DSEG7',
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: color,
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            Text(unit, style: TextStyle(color: skin.accent, fontSize: 9)),
          ],
        ),
      ],
    );
  }

  Color _coolColor(double? t) {
    if (t == null) return skin.faint;
    if (t >= profile.coolantDanger) return skin.bad;
    if (t >= profile.coolantWarn) return skin.warn;
    return skin.accent2;
  }

  Color _tempColor(double? t) {
    if (t == null) return skin.faint;
    if (t > 105) return skin.bad;
    if (t > 95) return skin.warn;
    return skin.accent2;
  }

  Color _voltColor(double? v) {
    if (v == null) return skin.faint;
    if (v < 12.5) return skin.bad;
    if (v > 14.6) return skin.warn;
    return skin.accent2;
  }
}
