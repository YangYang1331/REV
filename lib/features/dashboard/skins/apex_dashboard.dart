import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/race_widgets.dart';
import 'package:obd_dashboard/features/dashboard/widgets/rpm_bar.dart';
import 'package:obd_dashboard/features/dashboard/widgets/seven_readout.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// APEX 赛博霓虹仪表盘：品红+青色双霓虹，纯黑底，垂直转速条 + 中央巨车速
/// + 右侧水温/油耗 + 底部六格数据带 + 半透明机甲立绘。纯代码绘制，不依赖背景图。
class ApexDashboard extends StatelessWidget {
  const ApexDashboard({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });

  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  TextStyle get _label => TextStyle(
        color: skin.dim,
        fontSize: 10,
        letterSpacing: 2.5,
        fontWeight: FontWeight.w700,
      );

  Color? _coolantColor() {
    final c = data.coolant;
    if (c == null) return null;
    if (c >= profile.coolantDanger) return skin.bad;
    if (c >= profile.coolantWarn) return skin.warn;
    return skin.accent2;
  }

  String get _fuelValue =>
      data.fuelL100?.toStringAsFixed(1) ??
      data.fuelLph?.toStringAsFixed(1) ??
      '--';
  String get _fuelUnit => data.fuelL100 != null ? 'L/100km' : 'L/h';

  @override
  Widget build(BuildContext context) {
    return HorizonFxOverlay(
      accent: skin.accent,
      child: DecoratedBox(
        decoration: BoxDecoration(color: skin.background),
        child: Stack(
        children: [
          // —— 背景立绘：右侧半透明机甲女车手，纯黑底不再单调 ——
          Positioned(
            right: 0,
            bottom: 0,
            top: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.14,
                child: Image.asset(
                  'assets/images/avatar_pilot.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
          // —— 前景内容 ——
          Positioned.fill(
            child: OrientationBuilder(
              builder: (context, ori) =>
                  ori == Orientation.landscape ? _landscape() : _portrait(),
            ),
          ),
        ],
      ),
    ),
    );
  }

  // ════════════════════════ 横屏 ════════════════════════
  Widget _landscape() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.025, h * 0.06, w * 0.025, h * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // —— 顶部换挡灯条 ——
              ShiftLightBar(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                rpmDanger: profile.rpmDanger,
                height: h * 0.04,
                gap: 3,
                alarm: (data.coolant != null &&
                        data.coolant! >= profile.coolantDanger) ||
                    (data.voltage != null && data.voltage! < 11.5),
              ),
              SizedBox(height: h * 0.018),
              // —— 主体三栏 ——
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左栏：垂直转速条 + 刻度 + rpm
                    _verticalRpm(w * 0.13, h),
                    SizedBox(width: w * 0.02),
                    // 中栏：巨型车速 + 档位
                    Expanded(
                      child: BezelPanel(
                        stroke: skin.panelStroke,
                        fill: skin.panel,
                        glow: true,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('VEHICLE SPEED', style: _label),
                            SizedBox(height: h * 0.012),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SevenReadout(
                                  value: data.speed
                                      .toStringAsFixed(0)
                                      .padLeft(3, '0'),
                                  ghostWidth: 3,
                                  fontSize: h * 0.17,
                                  color: skin.accent,
                                  ghostColor:
                                      skin.accent.withOpacity(0.08),
                                ),
                                SizedBox(width: 10),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text('km/h',
                                      style: TextStyle(
                                          color: skin.dim,
                                          fontSize: 16,
                                          letterSpacing: 3)),
                                ),
                              ],
                            ),
                            SizedBox(height: h * 0.02),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('GEAR', style: _label),
                                SizedBox(width: 16),
                                GearWidget(
                                  gear: data.gear,
                                  color: skin.accent2,
                                  fontSize: h * 0.11,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: w * 0.02),
                    // 右栏：水温 + 油耗 + 电压
                    _rightPanel(w * 0.20, h),
                  ],
                ),
              ),
              SizedBox(height: h * 0.018),
              // —— 底部六格数据带 ——
              _dataStrip(h),
            ],
          ),
        ),
      );
    });
  }

  /// 左栏：垂直转速条（带刻度）+ rpm 大数字。
  Widget _verticalRpm(double width, double h) {
    const ticks = [0, 2000, 4000, 6000, 8000, 10000];
    return SizedBox(
      width: width,
      child: BezelPanel(
        stroke: skin.panelStroke,
        fill: skin.panel,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ENGINE RPM', style: _label),
            SizedBox(height: h * 0.012),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 刻度文字（从下到上 0→10000）
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ticks.reversed
                        .map((t) => Text(
                              t == 0 ? '0' : '${t ~/ 1000}k',
                              style: TextStyle(
                                color: skin.faint,
                                fontFamily: 'DSEG7',
                                fontSize: 9,
                              ),
                            ))
                        .toList(),
                  ),
                  SizedBox(width: 6),
                  // 垂直转速条
                  Expanded(
                    child: RpmBar(
                      rpm: data.rpm,
                      redline: profile.redlineRpm,
                      skin: skin,
                      axis: Axis.vertical,
                      segments: 20,
                      thickness: 14,
                      maxRpm: 10000,
                      activeColor: skin.accent,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SevenReadout(
                  value: data.rpm.toString().padLeft(4, '0'),
                  ghostWidth: 4,
                  fontSize: 20,
                  color: skin.accent,
                  ghostColor: skin.accent.withOpacity(0.08),
                ),
                SizedBox(width: 4),
                Text('rpm', style: TextStyle(color: skin.dim, fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 右栏：水温条 + 油耗 + 电压 + 进气温度。
  Widget _rightPanel(double width, double h) {
    return SizedBox(
      width: width,
      child: BezelPanel(
        stroke: skin.panelStroke,
        fill: skin.panel,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _metricRow('COOLANT',
                data.coolant?.toStringAsFixed(0) ?? '--',
                unit: '°C',
                valueColor: _coolantColor()),
            SizedBox(height: 6),
            TempGaugeBar(
              value: data.coolant,
              warn: profile.coolantWarn.toDouble(),
              danger: profile.coolantDanger.toDouble(),
              height: 10,
              segments: 16,
              showScale: false,
            ),
            SizedBox(height: h * 0.02),
            _metricRow('FUEL', _fuelValue, unit: _fuelUnit),
            SizedBox(height: h * 0.018),
            _metricRow('VOLTAGE',
                data.voltage?.toStringAsFixed(1) ?? '--',
                unit: 'V'),
            SizedBox(height: h * 0.018),
            _metricRow('INTAKE',
                data.intakeTemp?.toStringAsFixed(0) ?? '--',
                unit: '°C'),
            Spacer(),
            _metricRow('THROTTLE',
                data.throttle?.toStringAsFixed(0) ?? '--',
                unit: '%'),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value,
      {String? unit, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: _label),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SevenReadout(
              value: value.padLeft(4, ' '),
              ghostWidth: 4,
              fontSize: 18,
              color: valueColor ?? skin.accent2,
              ghostColor: (valueColor ?? skin.accent2).withOpacity(0.06),
            ),
            if (unit != null) ...[
              SizedBox(width: 3),
              Text(unit, style: TextStyle(color: skin.dim, fontSize: 9)),
            ],
          ],
        ),
      ],
    );
  }

  /// 底部六格数据带：MAF / LOAD / THROTTLE / VOLT / FUEL / TRIP。
  Widget _dataStrip(double h) {
    final items = <_StripItem>[
      _StripItem('MAF', data.maf?.toStringAsFixed(1) ?? '--', 'g/s'),
      _StripItem('LOAD', data.load?.toStringAsFixed(0) ?? '--', '%'),
      _StripItem(
          'BOOST', data.boost?.toStringAsFixed(2) ?? '--', 'bar'),
      _StripItem('VOLT', data.voltage?.toStringAsFixed(1) ?? '--', 'V'),
      _StripItem('FUEL', _fuelValue, _fuelUnit),
      _StripItem('TRIP', data.tripKm.toStringAsFixed(1), 'km'),
    ];
    return BezelPanel(
      stroke: skin.panelStroke,
      fill: skin.panel,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(items[i].label,
                      style: _label.copyWith(fontSize: 9)),
                  SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SevenReadout(
                        value: items[i].value.padLeft(5, ' '),
                        ghostWidth: 5,
                        fontSize: 16,
                        color: skin.accent2,
                        ghostColor: skin.accent2.withOpacity(0.05),
                      ),
                      SizedBox(width: 2),
                      Text(items[i].unit,
                          style:
                              TextStyle(color: skin.dim, fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ),
            if (i < items.length - 1)
              Container(width: 1, height: 28, color: skin.panelStroke),
          ],
        ],
      ),
    );
  }

  // ════════════════════════ 竖屏 ════════════════════════
  Widget _portrait() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.04, h * 0.05, w * 0.04, h * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShiftLightBar(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                rpmDanger: profile.rpmDanger,
                height: h * 0.032,
                gap: 3,
                alarm: (data.coolant != null &&
                        data.coolant! >= profile.coolantDanger) ||
                    (data.voltage != null && data.voltage! < 11.5),
              ),
              SizedBox(height: h * 0.015),
              // 转速条（水平）+ 刻度 + rpm
              BezelPanel(
                stroke: skin.panelStroke,
                fill: skin.panel,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('ENGINE RPM', style: _label),
                        Spacer(),
                        SevenReadout(
                          value: data.rpm.toString().padLeft(4, '0'),
                          ghostWidth: 4,
                          fontSize: 22,
                          color: skin.accent,
                          ghostColor: skin.accent.withOpacity(0.08),
                        ),
                        SizedBox(width: 4),
                        Text('rpm',
                            style: TextStyle(color: skin.dim, fontSize: 10)),
                      ],
                    ),
                    SizedBox(height: 6),
                    RpmScaleBar(
                      rpm: data.rpm,
                      redline: profile.redlineRpm,
                      skin: skin,
                      segments: 18,
                      thickness: 10,
                      maxScaleRpm: 10000,
                      activeColor: skin.accent,
                    ),
                  ],
                ),
              ),
              SizedBox(height: h * 0.018),
              // 中央车速 + 档位
              Expanded(
                child: BezelPanel(
                  stroke: skin.panelStroke,
                  fill: skin.panel,
                  glow: true,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('VEHICLE SPEED / GEAR', style: _label),
                      SizedBox(height: h * 0.015),
                      SevenReadout(
                        value:
                            data.speed.toStringAsFixed(0).padLeft(3, '0'),
                        ghostWidth: 3,
                        fontSize: h * 0.13,
                        color: skin.accent,
                        ghostColor: skin.accent.withOpacity(0.08),
                      ),
                      SizedBox(height: 4),
                      Text('km/h',
                          style: TextStyle(
                              color: skin.dim, fontSize: 14, letterSpacing: 3)),
                      SizedBox(height: h * 0.02),
                      GearWidget(
                        gear: data.gear,
                        color: skin.accent2,
                        fontSize: h * 0.09,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: h * 0.018),
              // 水温条
              BezelPanel(
                stroke: skin.panelStroke,
                fill: skin.panel,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('COOLANT', style: _label),
                        Spacer(),
                        SevenReadout(
                          value: (data.coolant?.toStringAsFixed(0) ?? '--')
                              .padLeft(2, ' '),
                          ghostWidth: 2,
                          fontSize: 20,
                          color: _coolantColor() ?? skin.accent2,
                          ghostColor: skin.accent2.withOpacity(0.06),
                        ),
                        SizedBox(width: 3),
                        Text('°C',
                            style: TextStyle(color: skin.dim, fontSize: 10)),
                      ],
                    ),
                    SizedBox(height: 6),
                    TempGaugeBar(
                      value: data.coolant,
                      warn: profile.coolantWarn.toDouble(),
                      danger: profile.coolantDanger.toDouble(),
                      height: 12,
                      segments: 20,
                    ),
                  ],
                ),
              ),
              SizedBox(height: h * 0.015),
              // 2×3 数据网格
              _portraitGrid(),
            ],
          ),
        ),
      );
    });
  }

  Widget _portraitGrid() {
    final items = <_StripItem>[
      _StripItem('FUEL', _fuelValue, _fuelUnit),
      _StripItem('VOLT', data.voltage?.toStringAsFixed(1) ?? '--', 'V'),
      _StripItem('MAF', data.maf?.toStringAsFixed(1) ?? '--', 'g/s'),
      _StripItem('LOAD', data.load?.toStringAsFixed(0) ?? '--', '%'),
      _StripItem('INTAKE', data.intakeTemp?.toStringAsFixed(0) ?? '--', '°C'),
      _StripItem('TRIP', data.tripKm.toStringAsFixed(1), 'km'),
    ];
    return BezelPanel(
      stroke: skin.panelStroke,
      fill: skin.panel,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var row = 0; row < 2; row++) ...[
            Row(
              children: [
                for (var col = 0; col < 3; col++) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Text(items[row * 3 + col].label,
                              style: _label.copyWith(fontSize: 9)),
                          SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              SevenReadout(
                                value: items[row * 3 + col]
                                    .value
                                    .padLeft(5, ' '),
                                ghostWidth: 5,
                                fontSize: 16,
                                color: skin.accent2,
                                ghostColor: skin.accent2.withOpacity(0.05),
                              ),
                              SizedBox(width: 2),
                              Text(items[row * 3 + col].unit,
                                  style: TextStyle(
                                      color: skin.dim, fontSize: 8)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (col < 2)
                    Container(width: 1, height: 32, color: skin.panelStroke),
                ],
              ],
            ),
            if (row == 0)
              Container(height: 1, color: skin.panelStroke),
          ],
        ],
      ),
    );
  }
}

class _StripItem {
  final String label;
  final String value;
  final String unit;
  const _StripItem(this.label, this.value, this.unit);
}
