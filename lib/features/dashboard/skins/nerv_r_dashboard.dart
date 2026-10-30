import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/race_widgets.dart';
import 'package:obd_dashboard/features/dashboard/widgets/seven_readout.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// NERV-R 赛道版：纯代码绘制，不依赖背景图。
/// 顶部 Haltech 风格换挡灯条（两侧向中央递进、红区全红闪烁）；
/// 中央巨型车速 + 大档位；底部青→橙温度分段条 + 高密度数据带。
/// 分区工整、信息密度高，横 / 竖屏均重新排版。
class NervRDashboard extends StatelessWidget {
  const NervRDashboard({
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
        fontSize: 11,
        letterSpacing: 2.5,
        fontWeight: FontWeight.w700,
      );

  Color? _coolantColor() {
    final c = data.coolant;
    if (c == null) return null;
    if (c >= profile.coolantDanger) return skin.bad;
    if (c >= profile.coolantWarn) return skin.warn;
    return skin.ok;
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
        decoration: BoxDecoration(
          // 纯黑底：赛车仪表标准，发光来自换挡灯 / 描边 / 数字本身，
          // 避免大面积彩色光斑的 AI 模板感。
          color: skin.background,
        ),
        child: Stack(
        children: [
          // —— 背景立绘：右侧半透明机甲女车手（原生版 avatar_pilot），
          // 低透明度只做氛围，不遮挡数据，纯黑底不再单调。——
          Positioned(
            right: 0,
            bottom: 0,
            top: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.16,
                child: Image.asset(
                  'assets/images/avatar_pilot.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
          // —— 前景仪表盘内容 ——
          Positioned.fill(
            child: OrientationBuilder(builder: (context, ori) {
              return ori == Orientation.landscape
                  ? _landscape()
                  : _portrait();
            }),
          ),
        ],
      ),
    ),
    );
  }

  // ════════════════════════════ 横屏 ════════════════════════════
  Widget _landscape() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.028, h * 0.075, w * 0.028, h * 0.035),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // —— 换挡灯条 ——
              ShiftLightBar(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                rpmDanger: profile.rpmDanger,
                height: h * 0.042,
                gap: 4,
                alarm: (data.coolant != null &&
                        data.coolant! >= profile.coolantDanger) ||
                    (data.voltage != null && data.voltage! < 11.5),
              ),
              SizedBox(height: h * 0.02),
              // —— 主面板：转速 / 车速 / 档位 ——
              Expanded(
                flex: 5,
                child: BezelPanel(
                  stroke: skin.panelStroke,
                  fill: skin.panel.withValues(alpha: 0.06),
                  corner: 20,
                  glow: true,
                  padding: EdgeInsets.symmetric(
                      horizontal: w * 0.022, vertical: h * 0.018),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 左：转速 + 车速
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('ENGINE RPM', style: _label),
                                const Spacer(),
                                SevenReadout(
                                  value: data.rpm.toString().padLeft(4, '0'),
                                  ghostWidth: 4,
                                  fontSize: h * 0.052,
                                  color: skin.accent,
                                  ghostColor:
                                      skin.accent.withValues(alpha: 0.08),
                                ),
                                SizedBox(width: 6),
                                Text('rpm',
                                    style: TextStyle(
                                        color: skin.dim, fontSize: 12)),
                              ],
                            ),
                            SizedBox(height: h * 0.012),
                            RpmScaleBar(
                              rpm: data.rpm,
                              redline: profile.redlineRpm,
                              skin: skin,
                              segments: 18,
                              thickness: h * 0.022,
                              maxScaleRpm: 10000,
                            ),
                            const Spacer(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                SevenReadout(
                                  value: data.speed
                                      .toStringAsFixed(0)
                                      .padLeft(3, '0'),
                                  ghostWidth: 3,
                                  fontSize: h * 0.235,
                                  color: skin.accent2,
                                  ghostColor:
                                      skin.accent2.withValues(alpha: 0.07),
                                ),
                                SizedBox(width: w * 0.01),
                                Padding(
                                  padding:
                                      EdgeInsets.only(bottom: h * 0.02),
                                  child: Text('km/h',
                                      style: TextStyle(
                                          color: skin.dim,
                                          fontSize: 16,
                                          letterSpacing: 2)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, margin: EdgeInsets.symmetric(horizontal: w*0.012), color: skin.panelStroke),
                      // 右：档位（上移）+ 空气流量 / 点火提前（右移到空白处）
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // —— 档位：靠上，避免与下方数据带挤在一起 ——
                            Text('GEAR / 档位', style: _label, textAlign: TextAlign.center),
                            SizedBox(height: h * 0.008),
                            GearWidget(
                              gear: data.gear,
                              color: skin.accent2,
                              fontSize: h * 0.175,
                            ),
                            Container(
                                height: 1,
                                margin: EdgeInsets.symmetric(vertical: h * 0.012),
                                color: skin.panelStroke),
                            // —— 空气流量 / 点火提前：利用右栏剩余空白 ——
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _sideStat('MAF 空气流量', data.maf, 'g/s'),
                                  _sideStat('IGN 点火提前', data.ignAdv, '°'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: h * 0.016),
              // —— 底部数据带 ——
              SizedBox(
                height: h * 0.272,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _tempPanel('COOLANT / 水温', data.coolant,
                        profile.coolantWarn.toDouble(), profile.coolantDanger.toDouble(), '°C', w)),
                    SizedBox(width: w * 0.012),
                    Expanded(child: _tempPanel('OIL TEMP / 油温', data.oilTemp,
                        115.0, 125.0, '°C', w)),
                    SizedBox(width: w * 0.012),
                    Expanded(
                        child: _dataPanel('POWER / 动力', [
                      _D('LOAD 负荷', data.load, '%'),
                      _D('THROTTLE 油门', data.throttle, '%'),
                      _D('LTFT 长期修正', data.ltft, '%'),
                    ])),
                    SizedBox(width: w * 0.012),
                    Expanded(
                        child: _dataPanel('VEHICLE / 整车', [
                      _D('VOLT 电压', data.voltage, 'V', digits: 1),
                      _D('FUEL 油耗', double.tryParse(_fuelValue), _fuelUnit),
                      _D('TRIP 里程', data.tripKm, 'km'),
                    ])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ── 温度面板（分段条 + 大数字）──
  Widget _tempPanel(
      String title, double? v, double warn, double danger, String unit, double w) {
    final color = v == null
        ? skin.accent
        : (v >= danger
            ? skin.bad
            : v >= warn
                ? skin.warn
                : skin.ok);
    return BezelPanel(
      stroke: skin.panelStroke,
      fill: skin.panel.withValues(alpha: 0.12),
      corner: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: _label),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SevenReadout(
                value: (v == null ? '--' : v.toStringAsFixed(0)).padLeft(3, ' '),
                ghostWidth: 3,
                fontSize: 30,
                color: color,
                ghostColor: color.withValues(alpha: 0.08),
              ),
              const SizedBox(width: 4),
              Text(unit, style: TextStyle(color: skin.dim, fontSize: 12)),
            ],
          ),
          TempGaugeBar(
            value: v,
            warn: warn,
            danger: danger,
            height: 12,
            segments: 22,
          ),
        ],
      ),
    );
  }

  // ── 数据面板（三行数字）──
  Widget _dataPanel(String title, List<_D> rows) {
    return BezelPanel(
      stroke: skin.panelStroke,
      fill: skin.panel.withValues(alpha: 0.12),
      corner: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _label),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: rows.map((d) => _dataRow(d)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(_D d) {
    final txt = d.value == null
        ? '--'
        : d.value!.toStringAsFixed(d.digits);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(d.label,
              style: TextStyle(color: skin.dim, fontSize: 9.5, letterSpacing: 0.5),
              overflow: TextOverflow.ellipsis),
        ),
        Text(txt,
            style: TextStyle(
                fontFamily: 'DSEG7',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: skin.ink)),
        const SizedBox(width: 3),
        SizedBox(
          width: 48,
          child: Text(d.unit,
              style: TextStyle(color: skin.dim, fontSize: 8.5, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  // ── 右栏小指标（空气流量 / 点火提前）：标签在上、大数字在下 ──
  Widget _sideStat(String label, double? v, String unit) {
    final txt = v == null ? '--' : v.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: skin.dim, fontSize: 10, letterSpacing: 1),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(txt,
                  style: TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: skin.ink)),
              const SizedBox(width: 4),
              Text(unit, style: TextStyle(color: skin.dim, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════ 竖屏 ════════════════════════════
  Widget _portrait() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.04, h * 0.07, w * 0.04, h * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShiftLightBar(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                rpmDanger: profile.rpmDanger,
                height: 14,
                gap: 3,
                alarm: (data.coolant != null &&
                        data.coolant! >= profile.coolantDanger) ||
                    (data.voltage != null && data.voltage! < 11.5),
              ),
              SizedBox(height: h * 0.012),
              // 主面板：转速 + 车速 + 档位
              Expanded(
                flex: 5,
                child: BezelPanel(
                  stroke: skin.panelStroke,
                  fill: skin.panel.withValues(alpha: 0.06),
                  corner: 18,
                  glow: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ENGINE RPM', style: _label),
                      SizedBox(height: h * 0.008),
                      RpmScaleBar(
                        rpm: data.rpm,
                        redline: profile.redlineRpm,
                        skin: skin,
                        segments: 18,
                        thickness: 10,
                        maxScaleRpm: 10000,
                      ),
                      const Spacer(),
                      Center(
                        child: SevenReadout(
                          value:
                              data.speed.toStringAsFixed(0).padLeft(3, '0'),
                          ghostWidth: 3,
                          fontSize: w * 0.24,
                          color: skin.accent2,
                          ghostColor:
                              skin.accent2.withValues(alpha: 0.07),
                        ),
                      ),
                      Center(
                        child: Text('km/h',
                            style: TextStyle(
                                color: skin.dim, fontSize: 14, letterSpacing: 3)),
                      ),
                      SizedBox(height: h * 0.012),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('GEAR  ', style: _label),
                            GearWidget(
                              gear: data.gear,
                              color: skin.accent2,
                              fontSize: w * 0.16,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              SizedBox(height: h * 0.012),
              // 水温
              SizedBox(
                height: h * 0.135,
                child: _tempPanel('COOLANT / 水温', data.coolant,
                    profile.coolantWarn.toDouble(), profile.coolantDanger.toDouble(), '°C', w),
              ),
              SizedBox(height: h * 0.012),
              // 数据网格 2×4
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _miniTile('油温', data.oilTemp, '°C', _coolantColor())),
                        SizedBox(width: 8),
                        Expanded(child: _miniTile('电压', data.voltage, 'V', null)),
                      ]),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _miniTile('MAF', data.maf, 'g/s', null)),
                        SizedBox(width: 8),
                        Expanded(child: _miniTile('负荷', data.load, '%', null)),
                      ]),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _miniTile('油耗', double.tryParse(_fuelValue), _fuelUnit, null)),
                        SizedBox(width: 8),
                        Expanded(child: _miniTile('里程', data.tripKm, 'km', null)),
                      ]),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _miniTile('油门', data.throttle, '%', null)),
                        SizedBox(width: 8),
                        Expanded(child: _miniTile('转速', data.rpm.toDouble(), 'rpm', null)),
                      ]),
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

  Widget _miniTile(String label, double? value, String unit, Color? color) {
    final txt = value == null
        ? '--'
        : (unit == 'rpm' || unit == '%' || unit == '°C'
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(1));
    return BezelPanel(
      stroke: skin.panelStroke,
      fill: skin.panel.withValues(alpha: 0.12),
      corner: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(color: skin.dim, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(txt,
                      style: TextStyle(
                          fontFamily: 'DSEG7',
                          fontWeight: FontWeight.bold,
                          fontSize: 26,
                          color: color ?? skin.ink)),
                ),
              ),
              const SizedBox(width: 3),
              Text(unit, style: TextStyle(color: skin.dim, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

class _D {
  _D(this.label, this.value, this.unit, {this.digits = 1});
  final String label;
  final double? value;
  final String unit;
  final int digits;
}
