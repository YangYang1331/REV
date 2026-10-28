import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/glass_panel.dart';
import 'package:obd_dashboard/features/dashboard/widgets/metric_tile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/rpm_bar.dart';
import 'package:obd_dashboard/features/dashboard/widgets/seven_readout.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// Metro 玻璃磁贴仪表盘。
/// 左侧：巨型车速 + 档位 + 转速条；右侧：玻璃磁贴网格（按支持度分级）。
class MetroDashboard extends StatelessWidget {
  const MetroDashboard({
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.8, -0.6),
            radius: 1.3,
            colors: [
              (skin.glowColor ?? skin.accent).withOpacity(0.22),
              skin.background,
            ],
          ),
        ),
        child: SafeArea(
          child: OrientationBuilder(builder: (context, ori) {
            final landscape = ori == Orientation.landscape;
            return landscape ? _landscape() : _portrait();
          }),
        ),
      ),
    );
  }

  // —— 左：速度 / 档位 / 转速 ——
  Widget _hero(double maxSpeedFont) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 车速整行（大数字+km/h）等比缩放：在左 Expanded 可用宽度内自适应，
        // 窄屏/高 dpr 车机上不再溢出盖住右侧磁贴；宽屏 scale=1.0 不变。
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SevenReadout(
                value: data.speed.toStringAsFixed(0).padLeft(3, '0'),
                ghostWidth: 3,
                fontSize: maxSpeedFont,
                color: skin.accent,
                ghostColor: skin.accent.withOpacity(0.08),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('km/h',
                    style: TextStyle(
                        color: skin.dim,
                        fontSize: maxSpeedFont * 0.18,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            GearWidget(
              gear: data.gear,
              color: skin.ink,
              fontSize: maxSpeedFont * 0.62,
              // metro 亮数码管上把幽灵位压到几乎不可见，避免真实档位细笔画外
              // 透出一个“全亮 8”；仅 metro 覆盖，其他皮肤沿用默认。
              ghostColor: skin.ink.withOpacity(0.06),
            ),
            const SizedBox(width: 16),
            Text('档位',
                style: TextStyle(
                    color: skin.dim, fontSize: 14, letterSpacing: 4)),
            const SizedBox(width: 28),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text.rich 会合并 DefaultTextStyle，单位段能拿到正常 UI 字体；
                // 单位用系统 UI 字体（七段数码管无法显示 / k m，会乱码）。
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: data.fuelL100 == null
                            ? '${data.fuelLph?.toStringAsFixed(1) ?? "--"} '
                            : '${data.fuelL100!.toStringAsFixed(1)} ',
                        style: TextStyle(
                            color: skin.accent2,
                            fontFamily: 'DSEG7',
                            fontSize: maxSpeedFont * 0.22,
                            fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: data.fuelL100 == null ? 'L/h' : 'L/100km',
                        style: TextStyle(
                            color: skin.accent2,
                            fontSize: maxSpeedFont * 0.13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Text('瞬时油耗',
                    style: TextStyle(color: skin.dim, fontSize: 11)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        RpmBar(
          rpm: data.rpm,
          redline: profile.redlineRpm,
          skin: skin,
          axis: Axis.horizontal,
          segments: 24,
          thickness: 14,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SevenReadout(
                  value: '${data.rpm}',
                  digits: 4,
                  fontSize: 18,
                  color: skin.dim,
                ),
                const SizedBox(width: 4),
                Text('RPM',
                    style: TextStyle(
                        color: skin.dim,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            Text('${profile.redlineRpm} REDLINE',
                style: TextStyle(color: skin.faint, fontSize: 11, letterSpacing: 1)),
          ],
        ),
      ],
    );
  }

  List<_Metric> _metricList() {
    return <_Metric>[
      _Metric('水温', data.coolant, '°C', color: _coolantColor()),
      _Metric('机油温', data.oilTemp, '°C'),
      _Metric('进气温', data.intakeTemp, '°C'),
      _Metric('电瓶', data.voltage, 'V', digits: 2),
      _Metric('增压', data.boost, 'bar', digits: 2),
      _Metric('空气流量', data.maf, 'g/s'),
      _Metric('负荷', data.load, '%'),
      _Metric('油门', data.throttle, '%'),
      _Metric('油位', data.fuelLevel, '%'),
      _Metric('点火提前', data.ignAdv, '°', digits: 1),
      _Metric('长期修正', data.ltft, '%'),
      _Metric('海拔', data.altitude, 'm'),
    ]..removeWhere((m) => !data.showUnsupportedAsDashes && m.value == null);
  }

  // —— 右：玻璃磁贴 ——
  Widget _tiles(int crossAxisCount, double fontScale, {double? aspectRatio}) {
    final tiles = _metricList();
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: aspectRatio == null,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: aspectRatio ?? 1.75,
      children: tiles
          .map((m) => GlassPanel(
                fill: skin.panel,
                stroke: skin.panelStroke,
                blur: 14,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: MetricTile(
                  label: m.label,
                  value: m.value,
                  unit: m.unit,
                  skin: skin,
                  digits: m.digits,
                  fontSize: 26 * fontScale,
                  compact: true,
                  valueColor: m.color,
                ),
              ))
          .toList(),
    );
  }

  Color? _coolantColor() {
    final c = data.coolant;
    if (c == null) return null;
    if (c >= profile.coolantDanger) return skin.bad;
    if (c >= profile.coolantWarn) return skin.warn;
    return null;
  }

  Widget _landscape() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: _hero(120),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 6,
            child: _tiles(4, 0.92),
          ),
        ],
      ),
    );
  }

  Widget _portrait() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          _hero(84),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              const cols = 3;
              final rows = (_metricList().length / cols).ceil();
              const gap = 10.0;
              final cellW = (c.maxWidth - (cols - 1) * gap) / cols;
              final cellH = (c.maxHeight - (rows - 1) * gap) / rows;
              return _tiles(cols, 1.0, aspectRatio: cellW / cellH);
            }),
          ),
        ],
      ),
    );
  }
}

class _Metric {
  _Metric(this.label, this.value, this.unit,
      {this.digits = 1, this.color});
  final String label;
  final double? value;
  final String unit;
  final int digits;
  final Color? color;
}
