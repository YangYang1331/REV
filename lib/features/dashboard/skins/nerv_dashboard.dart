import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/background_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/race_widgets.dart';
import 'package:obd_dashboard/features/dashboard/widgets/seven_readout.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// NERV 赤色诊断风：数据嵌入背景六边形面板，右区避让明日香立绘。
class NervDashboard extends StatelessWidget {
  const NervDashboard({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });
  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  Widget _slot({
    required double l,
    required double t,
    required double r,
    required double b,
    required Widget child,
    Alignment alignment = Alignment.topLeft,
  }) {
    return Positioned(
      left: l,
      top: t,
      right: r,
      bottom: b,
      child: Align(alignment: alignment, child: child),
    );
  }

  Widget _label(String s) => Text(s,
      style: TextStyle(
          color: skin.dim,
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w600));

  @override
  Widget build(BuildContext context) {
    return HorizonFxOverlay(
      accent: skin.accent,
      child: SkinBackground(
        skin: skin,
        dim: 0.42,
        child: OrientationBuilder(builder: (context, ori) {
          return ori == Orientation.landscape ? _landscape() : _portrait();
        }),
      ),
    );
  }

  Widget _landscape() {
    return LayoutBuilder(builder: (context, c) {
      // 用屏幕尺寸比例定位（与背景六边形面板对齐）
      final w = c.maxWidth;
      final h = c.maxHeight;
      return Stack(children: [
        // —— 第二行面板：横向转速条（带 0–10000 刻度，复刻原版）——
        _slot(
          l: w * 0.045,
          t: h * 0.185,
          r: w * 0.30,
          b: h * 0.705,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _label('ENGINE RPM / 引擎转速'),
                  const Spacer(),
                  SevenReadout(
                    value: data.rpm.toString().padLeft(4, '0'),
                    ghostWidth: 4,
                    fontSize: 26,
                    color: skin.accent2,
                    ghostColor: skin.accent2.withOpacity(0.1),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('rpm',
                        style: TextStyle(color: skin.dim, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              RpmScaleBar(
                rpm: data.rpm,
                redline: profile.redlineRpm,
                skin: skin,
                segments: 18,
                thickness: 11,
                maxScaleRpm: 10000,
                activeColor: skin.accent2,
              ),
            ],
          ),
        ),
        // —— 大面板左区：巨型车速 + 档位（避开右区立绘）——
        _slot(
          l: w * 0.05,
          t: h * 0.34,
          r: w * 0.42,
          b: h * 0.32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _label('VEHICLE SPEED / GEAR'),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SevenReadout(
                    value: data.speed.toStringAsFixed(0).padLeft(3, '0'),
                    ghostWidth: 3,
                    fontSize: h * 0.155,
                    color: skin.accent,
                    ghostColor: skin.accent.withOpacity(0.08),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('km/h',
                        style: TextStyle(
                            color: skin.dim, fontSize: 16, letterSpacing: 2)),
                  ),
                  const SizedBox(width: 24),
                  GearWidget(
                    gear: data.gear,
                    color: skin.accent2,
                    fontSize: h * 0.12,
                  ),
                ],
              ),
            ],
          ),
        ),
        // —— 底部左面板：水温分段条（青→橙，复刻原版 0/40/80/120）——
        _slot(
          l: w * 0.045,
          t: h * 0.71,
          r: w * 0.52,
          b: h * 0.07,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  _label('COOLANT TEMP / 水温'),
                  const Spacer(),
                  SevenReadout(
                    value: (data.coolant == null
                            ? '--'
                            : data.coolant!.toStringAsFixed(0))
                        .padLeft(3, ' '),
                    ghostWidth: 3,
                    fontSize: 30,
                    color: _coolantColor() ?? skin.accent,
                    ghostColor: skin.accent.withOpacity(0.06),
                  ),
                  const SizedBox(width: 3),
                  Text('°C',
                      style: TextStyle(color: skin.dim, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),
              TempGaugeBar(
                value: data.coolant,
                warn: profile.coolantWarn.toDouble(),
                danger: profile.coolantDanger.toDouble(),
                height: 14,
                segments: 24,
              ),
            ],
          ),
        ),
        // —— 底部右面板：燃油 / 里程 / 平均油耗 / 电压（2×2）——
        _slot(
          l: w * 0.555,
          t: h * 0.71,
          r: w * 0.20,
          b: h * 0.07,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _block('nerv-fuel', '瞬时油耗',
                            data.fuelL100?.toStringAsFixed(1) ??
                                data.fuelLph?.toStringAsFixed(1) ??
                                '--',
                            data.fuelL100 != null ? 'L/100km' : 'L/h',
                            compact: true)),
                    _divider(),
                    Expanded(
                        child: _block('nerv-mileage', '本次里程',
                            data.tripKm.toStringAsFixed(1), 'km',
                            compact: true)),
                  ],
                ),
              ),
              Container(height: 1, color: skin.panelStroke.withOpacity(0.5)),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _block('nerv-l100', '平均油耗',
                            data.tripL100?.toStringAsFixed(1) ?? '--',
                            'L/100km',
                            compact: true)),
                    _divider(),
                    Expanded(
                        child: _block('voltage', '电瓶电压',
                            data.voltage?.toStringAsFixed(1) ?? '--', 'V',
                            compact: true)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // —— 底部中央：DATA LINK 数据链路状态条（复刻原版）——
        _slot(
          l: w * 0.38,
          t: h * 0.885,
          r: w * 0.38,
          b: h * 0.04,
          alignment: Alignment.center,
          child: _dataLink(),
        ),
        // 注：“OBD-II INTERFACE / SYNC” 已内置在 NERV 背景图中，不再叠加。
        // —— 右上角：数据丢失徽标（仅在丢失时出现，避免与背景重复）——
        if (data.dataLost)
          _slot(
            l: 0,
            t: h * 0.02,
            r: w * 0.04,
            b: 0,
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: skin.warn.withOpacity(0.18),
                border: Border.all(color: skin.warn, width: 1.5),
              ),
              child: Text('DATA LOST',
                  style: TextStyle(
                      color: skin.warn,
                      fontSize: 15,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ]);
    });
  }

  Color? _coolantColor() {
    final c = data.coolant;
    if (c == null) return null;
    if (c >= profile.coolantDanger) return skin.bad;
    if (c >= profile.coolantWarn) return skin.warn;
    return skin.accent;
  }

  /// 原版底部中央 DATA LINK 数据链路状态条。
  Widget _dataLink() {
    final ok = data.connected && !data.dataLost;
    final fill = ok ? 0.82 : 0.18;
    final color = ok ? skin.accent2 : skin.bad;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('DATA LINK',
            style: TextStyle(
                color: skin.dim,
                fontSize: 8,
                letterSpacing: 2,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: skin.panelStroke.withOpacity(0.35),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fill,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _block(String key, String label, String value, String unit,
      {Color? valueColor, bool compact = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            style: TextStyle(
                color: skin.dim,
                fontSize: compact ? 9 : 11,
                letterSpacing: compact ? 1 : 2,
                fontWeight: FontWeight.w600)),
        SizedBox(height: compact ? 3 : 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SevenReadout(
              value: value.padLeft(compact ? 4 : 4, ' '),
              ghostWidth: compact ? 3 : 4,
              fontSize: compact ? 20 : 30,
              color: valueColor ?? skin.accent,
              ghostColor: (valueColor ?? skin.accent).withOpacity(0.05),
            ),
            const SizedBox(width: 4),
            Text(unit,
                style: TextStyle(
                    color: skin.dim,
                    fontSize: compact ? 8.5 : 12,
                    letterSpacing: 0.5)),
          ],
        ),
      ],
    );
  }

  Widget _portrait() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— 顶部标题（竖屏无背景图，用文字还原 NERV 标题）——
              Row(
                children: [
                  Text('NERV',
                      style: TextStyle(
                          color: skin.accent,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3)),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('車両状態診断',
                          style: TextStyle(
                              color: skin.accent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text('VEHICLE DIAGNOSTIC',
                          style: TextStyle(
                              color: skin.dim,
                              fontSize: 11,
                              letterSpacing: 2)),
                    ],
                  ),
                  const Spacer(),
                  // 标题右侧斜纹装饰
                  Row(
                    children: List.generate(
                        6,
                        (i) => Container(
                              width: 10,
                              height: 4,
                              margin: const EdgeInsets.only(right: 2),
                              color: skin.accent.withOpacity(i < 4 ? 0.9 : 0.3),
                            )),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // —— ENGINE RPM 面板 ——
              _hexPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('ENGINE RPM'),
                    const SizedBox(height: 6),
                    RpmScaleBar(
                      rpm: data.rpm,
                      redline: profile.redlineRpm,
                      skin: skin,
                      segments: 18,
                      thickness: 10,
                      maxScaleRpm: 10000,
                      activeColor: skin.accent2,
                    ),
                    const SizedBox(height: 4),
                    SevenReadout(
                      value: data.rpm.toString().padLeft(4, '0'),
                      ghostWidth: 4,
                      fontSize: 24,
                      color: skin.accent,
                      ghostColor: skin.accent.withOpacity(0.06),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // —— VEHICLE SPEED / GEAR 面板 ——
              Expanded(
                child: _hexPanel(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _label('VEHICLE SPEED / GEAR'),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SevenReadout(
                            value: data.speed.toStringAsFixed(0).padLeft(3, '0'),
                            ghostWidth: 3,
                            fontSize: w * 0.20,
                            color: skin.accent,
                            ghostColor: skin.accent.withOpacity(0.06),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text('km/h',
                                style: TextStyle(
                                    color: skin.dim,
                                    fontSize: 16,
                                    letterSpacing: 2)),
                          ),
                          const Spacer(),
                          GearWidget(
                            gear: data.gear,
                            color: skin.accent2,
                            fontSize: w * 0.15,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // —— 底部数据面板：油耗三栏 + 水温/电压 ——
              _hexPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: _block(
                                'f',
                                '瞬时油耗',
                                data.fuelL100?.toStringAsFixed(1) ??
                                    data.fuelLph?.toStringAsFixed(1) ??
                                    '--',
                                data.fuelL100 != null ? 'L/100km' : 'L/h')),
                        _divider(),
                        Expanded(
                            child: _block('m', '本次里程',
                                data.tripKm.toStringAsFixed(1), 'km')),
                        _divider(),
                        Expanded(
                            child: _block(
                                'a',
                                '平均油耗',
                                data.tripL100?.toStringAsFixed(1) ?? '--',
                                'L/100km')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(height: 1, color: skin.panelStroke),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 水温：数字 + 青→橙分段条
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('冷却液温'),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  SevenReadout(
                                    value: (data.coolant == null
                                            ? '--'
                                            : data.coolant!.toStringAsFixed(0))
                                        .padLeft(3, ' '),
                                    ghostWidth: 3,
                                    fontSize: 22,
                                    color: _coolantColor() ?? skin.accent,
                                    ghostColor:
                                        skin.accent.withOpacity(0.06),
                                  ),
                                  const SizedBox(width: 3),
                                  Text('°C',
                                      style: TextStyle(
                                          color: skin.dim, fontSize: 10)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              TempGaugeBar(
                                value: data.coolant,
                                warn: profile.coolantWarn.toDouble(),
                                danger: profile.coolantDanger.toDouble(),
                                height: 10,
                                segments: 18,
                                showScale: false,
                              ),
                            ],
                          ),
                        ),
                        _divider(),
                        Expanded(
                          flex: 2,
                          child: _block('v', '电瓶电压',
                              data.voltage?.toStringAsFixed(1) ?? '--', 'V',
                              compact: true)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // —— 底部状态栏 ——
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OBD-II INTERFACE',
                          style: TextStyle(
                              color: skin.accent,
                              fontSize: 11,
                              letterSpacing: 1,
                              fontWeight: FontWeight.bold)),
                      Text(
                          profile.id == 'game'
                              ? 'MODEL: TELEMETRY'
                              : 'MODEL: NERV-2000',
                          style: TextStyle(
                              color: skin.dim, fontSize: 10, letterSpacing: 1)),
                    ],
                  ),
                  const Spacer(),
                  Text(data.dataLost ? 'LOST' : 'SYNC',
                      style: TextStyle(
                          color: data.dataLost ? skin.warn : skin.accent,
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _divider() => Container(
      width: 1, height: 36, color: skin.panelStroke.withOpacity(0.6));

  /// 六边形风格面板（竖屏用切角矩形描边模拟）。
  Widget _hexPanel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: skin.panel.withOpacity(0.25),
        border: Border.all(color: skin.panelStroke, width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}
