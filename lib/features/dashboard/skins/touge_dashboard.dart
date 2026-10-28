import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/background_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/brand_logo.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/rpm_bar.dart';
import 'package:obd_dashboard/features/dashboard/widgets/seven_readout.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// Touge 水墨山路风：数据集中在左侧暗色区，笔触式转速条，白/红数码管。
class TougeDashboard extends StatelessWidget {
  const TougeDashboard({
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
      child: SkinBackground(
        skin: skin,
        dim: 0.30,
        child: OrientationBuilder(builder: (context, ori) {
          return ori == Orientation.landscape ? _landscape() : _portrait();
        }),
      ),
    );
  }

  Widget _label(String s) => Text(s,
      style: TextStyle(
          color: skin.dim,
          fontSize: 11,
          letterSpacing: 3,
          fontWeight: FontWeight.w600));

  Widget _read(String v, int w, double size, Color c) => SevenReadout(
        value: v.padLeft(w, ' '),
        ghostWidth: w,
        fontSize: size,
        color: c,
        ghostColor: skin.ink.withOpacity(0.06),
      );

  Widget _landscape() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return Stack(children: [
        // REV 品牌标识（背景图里旧的「山轉」logo 已抹除）
        Positioned(
          left: w * 0.018,
          top: h * 0.022,
          child: RevBrandLogo(
            size: h * 0.072,
            color: skin.ink,
            accent: skin.accent,
            titleColor: skin.ink,
            subtitle: 'TOUGE',
          ),
        ),
        // 主读区：左侧暗区
        Positioned(
          left: w * 0.045,
          top: h * 0.16,
          right: w * 0.42,
          bottom: h * 0.12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('SPEED'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _read(data.speed.toStringAsFixed(0), 3, h * 0.19, skin.ink),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('km/h',
                        style: TextStyle(
                            color: skin.dim, fontSize: 15, letterSpacing: 2)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              BrushRpmBar(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                color: skin.accent,
                height: 9,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  GearWidget(
                    gear: data.gear,
                    color: skin.accent,
                    fontSize: h * 0.10,
                  ),
                  const SizedBox(width: 18),
                  _read(data.rpm.toString(), 5, h * 0.045, skin.ink),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('RPM',
                        style: TextStyle(color: skin.dim, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 次读区：左下
        Positioned(
          left: w * 0.045,
          right: w * 0.50,
          bottom: h * 0.04,
          child: Column(
            children: [
              Divider(color: skin.panelStroke, height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _mini('冷却液', data.coolant?.toStringAsFixed(0) ?? '--', '°C',
                      _coolantColor()),
                  _mini('电瓶', data.voltage?.toStringAsFixed(1) ?? '--', 'V', null),
                  _mini('负荷', data.load?.toStringAsFixed(0) ?? '--', '%', null),
                  _mini('油门', data.throttle?.toStringAsFixed(0) ?? '--', '%', null),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _mini('瞬时油耗', data.fuelL100?.toStringAsFixed(1) ??
                      data.fuelLph?.toStringAsFixed(1) ?? '--',
                      data.fuelL100 != null ? 'L/100km' : 'L/h', skin.accent),
                  _mini('里程', data.tripKm.toStringAsFixed(1), 'km', null),
                  _mini('平均', data.tripL100?.toStringAsFixed(1) ?? '--', 'L/100km', null),
                ],
              ),
            ],
          ),
        ),
      ]);
    });
  }

  Widget _mini(String label, String value, String unit, Color? vc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: vc ?? skin.ink)),
            const SizedBox(width: 3),
            Text(unit,
                style: TextStyle(color: skin.dim, fontSize: 10, letterSpacing: 1)),
          ],
        ),
      ],
    );
  }

  Color? _coolantColor() {
    final c = data.coolant;
    if (c == null) return null;
    if (c >= profile.coolantDanger) return skin.bad;
    if (c >= profile.coolantWarn) return skin.warn;
    return null;
  }

  Widget _portrait() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— REV 品牌标识 ——
              RevBrandLogo(
                size: 38,
                color: skin.ink,
                accent: skin.accent,
                titleColor: skin.ink,
                subtitle: 'TOUGE',
              ),
              const SizedBox(height: 18),
              // —— 主读区：车速 + 转速 + 档位 ——
              _label('VEHICLE SPEED'),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _read(data.speed.toStringAsFixed(0), 3, w * 0.22, skin.ink),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('km/h',
                        style: TextStyle(
                            color: skin.dim, fontSize: 16, letterSpacing: 2)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BrushRpmBar(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                color: skin.accent,
                height: 9,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  GearWidget(
                      gear: data.gear, color: skin.accent, fontSize: w * 0.13),
                  const SizedBox(width: 18),
                  _read(data.rpm.toString(), 5, w * 0.065, skin.ink),
                  const SizedBox(width: 6),
                  Text('RPM',
                      style: TextStyle(color: skin.dim, fontSize: 13)),
                ],
              ),
              const Spacer(),
              // —— 底部数据区 ——
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(color: skin.panelStroke, width: 1)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _mini('冷却液', data.coolant?.toStringAsFixed(0) ?? '--',
                            '°C', _coolantColor()),
                        _mini('电瓶', data.voltage?.toStringAsFixed(1) ?? '--',
                            'V', null),
                        _mini('负荷', data.load?.toStringAsFixed(0) ?? '--',
                            '%', null),
                        _mini('油门', data.throttle?.toStringAsFixed(0) ?? '--',
                            '%', null),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _mini(
                            '瞬时油耗',
                            data.fuelL100?.toStringAsFixed(1) ??
                                data.fuelLph?.toStringAsFixed(1) ??
                                '--',
                            data.fuelL100 != null ? 'L/100km' : 'L/h',
                            skin.accent),
                        _mini('里程', data.tripKm.toStringAsFixed(1), 'km', null),
                        _mini('平均', data.tripL100?.toStringAsFixed(1) ?? '--',
                            'L/100km', null),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
