import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/gear_widget.dart';
import 'package:obd_dashboard/features/dashboard/widgets/seven_readout.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 琥珀 NERV 诊断（第 10 套皮肤）：暖橙 NERV 实拍 1:1 复刻。
/// 顶部 NERV 叶片标识 + 車両状態診断 + 危险斜纹 + 琥珀时钟；
/// 40 段黄→琥珀→橙→红渐变转速条；巨车速 + 无头盔立绘；
/// 青→黄→红水温分段条；FUEL / MILEAGE 双卡；DATA LINK 页脚。
/// 纯代码绘制，不依赖烘焙背景图，横竖屏适配。
class AmberNervDashboard extends StatelessWidget {
  const AmberNervDashboard({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });

  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  // 转速条渐变（黄 → 琥珀 → 橙 → 红）
  static const _rpmStops = [
    _SegStop(0.00, Color(0xFFFFE06A)),
    _SegStop(0.45, Color(0xFFFFD24A)),
    _SegStop(0.68, Color(0xFFFFA818)),
    _SegStop(0.86, Color(0xFFFF6A1C)),
    _SegStop(1.00, Color(0xFFFF3820)),
  ];
  // 水温条渐变（青 → 黄 → 红）
  static const _coolStops = [
    _SegStop(0.00, Color(0xFF37C8D6)),
    _SegStop(0.45, Color(0xFF6FE0C0)),
    _SegStop(0.62, Color(0xFFFFD24A)),
    _SegStop(0.82, Color(0xFFFF9A1C)),
    _SegStop(1.00, Color(0xFFFF3820)),
  ];

  Color _rpmSegColor(double t) {
    for (var i = 0; i < _rpmStops.length - 1; i++) {
      if (t <= _rpmStops[i + 1].t) {
        final a = _rpmStops[i];
        final b = _rpmStops[i + 1];
        final f = (t - a.t) / (b.t - a.t);
        return Color.lerp(a.c, b.c, f)!;
      }
    }
    return _rpmStops.last.c;
  }

  Color _coolSegColor(double t) {
    for (var i = 0; i < _coolStops.length - 1; i++) {
      if (t <= _coolStops[i + 1].t) {
        final a = _coolStops[i];
        final b = _coolStops[i + 1];
        final f = (t - a.t) / (b.t - a.t);
        return Color.lerp(a.c, b.c, f)!;
      }
    }
    return _coolStops.last.c;
  }

  Color? _coolantColor() {
    final c = data.coolant;
    if (c == null) return null;
    if (c >= profile.coolantDanger) return skin.bad;
    if (c >= profile.coolantWarn) return skin.warn;
    return skin.accent;
  }

  Widget _label(String s, {double size = 11}) => Text(s,
      style: TextStyle(
          color: skin.dim,
          fontSize: size,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700));

  @override
  Widget build(BuildContext context) {
    return HorizonFxOverlay(
      accent: skin.accent,
      child: DecoratedBox(
        decoration: BoxDecoration(color: skin.background),
        child: OrientationBuilder(builder: (context, ori) {
          return ori == Orientation.landscape ? _landscape() : _portrait();
        }),
      ),
    );
  }

  /// 无头盔立绘（右下层）。
  Widget _avatar(double w, double h,
      {required double top,
      required double bottom,
      required double widthFrac,
      required double opacity}) {
    return Positioned(
      right: 0,
      top: top,
      bottom: bottom,
      width: w * widthFrac,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Image.asset(
            'assets/images/avatar_amber.png',
            fit: BoxFit.contain,
            alignment: Alignment.bottomRight,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════ 横屏 ════════════════════════════
  Widget _landscape() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return Stack(children: [
        // —— 无头盔立绘（右侧，头部约 28% 起）——
        _avatar(w, h,
            top: h * 0.20, bottom: 0, widthFrac: 0.30, opacity: 1.0),
        // —— 顶部 Header ——
        Positioned(
          left: w * 0.02,
          top: h * 0.015,
          right: w * 0.02,
          height: h * 0.13,
          child: _Header(skin: skin),
        ),
        // —— ENGINE RPM 区 ——
        Positioned(
          left: w * 0.045,
          top: h * 0.155,
          right: w * 0.25,
          height: h * 0.145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('ENGINE RPM / 回転数', size: 12),
              const SizedBox(height: 4),
              Expanded(
                child: _SegmentBar(
                  segments: 40,
                  fill: (data.rpm / 10000).clamp(0.0, 1.0),
                  colorAt: _rpmSegColor,
                  tickColor: skin.faint,
                ),
              ),
              const SizedBox(height: 2),
              _scaleRow(const [0, 2000, 4000, 6000, 8000, 10000]),
            ],
          ),
        ),
        // 右侧大转速数字
        Positioned(
          right: w * 0.02,
          top: h * 0.15,
          height: h * 0.16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SevenReadout(
                value: data.rpm.toString(),
                ghostWidth: 4,
                fontSize: h * 0.09,
                color: skin.accent,
                ghostColor: skin.accent.withValues(alpha: 0.08),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('rpm',
                    style: TextStyle(color: skin.dim, fontSize: 12)),
              ),
            ],
          ),
        ),
        // —— 中央巨车速 + 档位（左侧，避让右侧立绘）——
        Positioned(
          left: w * 0.05,
          top: h * 0.30,
          right: w * 0.42,
          bottom: h * 0.36,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 单个大数字，不补零（速度 0 显示单个 "0"）
              Text(
                data.speed.toStringAsFixed(0),
                style: TextStyle(
                  fontFamily: 'DSEG7',
                  fontWeight: FontWeight.bold,
                  fontSize: h * 0.22,
                  color: skin.accent,
                  height: 0.9,
                  shadows: [
                    Shadow(
                        color: skin.accent.withValues(alpha: 0.5),
                        blurRadius: 26),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('km/h',
                    style: TextStyle(
                        color: skin.dim,
                        fontSize: 18,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              GearWidget(
                gear: data.gear,
                color: skin.accent2,
                fontSize: h * 0.13,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        // —— 底部水温卡（左）——
        Positioned(
          left: w * 0.02,
          right: w * 0.50,
          top: h * 0.66,
          bottom: h * 0.085,
          child: _Panel(
            skin: skin,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('COOLANT TEMP / 水温', size: 12),
                const SizedBox(height: 8),
                Expanded(
                  child: _SegmentBar(
                    segments: 24,
                    fill: ((data.coolant ?? 0) / 120).clamp(0.0, 1.0),
                    colorAt: _coolSegColor,
                    tickColor: skin.faint,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _scaleRow(const [0, 40, 80, 120])),
                    const SizedBox(width: 10),
                    SevenReadout(
                      value: (data.coolant == null
                              ? '--'
                              : data.coolant!.toStringAsFixed(0))
                          .padLeft(2, ' '),
                      ghostWidth: 2,
                      fontSize: 30,
                      color: _coolantColor() ?? skin.accent,
                      ghostColor: skin.accent.withValues(alpha: 0.08),
                    ),
                    const SizedBox(width: 2),
                    Text('°C', style: TextStyle(color: skin.dim, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // —— 底部 FUEL / MILEAGE 双卡（右）——
        Positioned(
          left: w * 0.525,
          right: w * 0.02,
          top: h * 0.66,
          bottom: h * 0.085,
          child: _Panel(
            skin: skin,
            fillAlpha: 0.34,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: _FuelCard(
                    skin: skin,
                    label: 'FUEL / 燃費',
                    value: data.fuelLph?.toStringAsFixed(1) ??
                        data.fuelL100?.toStringAsFixed(1) ??
                        '--',
                    unit: data.fuelLph != null ? 'L/h' : 'L/100km',
                  ),
                ),
                Container(width: 1, color: skin.panelStroke),
                Expanded(
                  child: _FuelCard(
                    skin: skin,
                    label: 'MILEAGE / 走行距離',
                    value: data.tripKm.toStringAsFixed(1),
                    unit: 'km',
                  ),
                ),
              ],
            ),
          ),
        ),
        // —— 页脚 ——
        Positioned(
          left: w * 0.02,
          right: w * 0.02,
          bottom: h * 0.012,
          height: h * 0.06,
          child: _Footer(skin: skin, connected: data.connected && !data.dataLost),
        ),
        if (data.dataLost)
          Positioned(
            right: w * 0.30,
            top: h * 0.02,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: skin.warn.withValues(alpha: 0.16),
                border: Border.all(color: skin.warn, width: 1.5),
              ),
              child: Text('DATA LOST',
                  style: TextStyle(
                      color: skin.warn,
                      fontSize: 13,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ]);
    });
  }

  Widget _scaleRow(List<int> ticks) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: ticks
          .map((t) => Text(
                t == 0 ? '0' : '$t',
                style: TextStyle(
                  color: skin.faint,
                  fontFamily: 'DSEG7',
                  fontSize: 11,
                ),
              ))
          .toList(),
    );
  }

  // ════════════════════════════ 竖屏 ════════════════════════════
  Widget _portrait() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return SafeArea(
        child: Stack(
          children: [
            // 右下角淡立绘（背景氛围，面板在其上）
            _avatar(w, h,
                top: h * 0.58,
                bottom: 0,
                widthFrac: 0.62,
                opacity: 0.30),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(skin: skin, compact: true),
              const SizedBox(height: 12),
              // ENGINE RPM
              _Panel(
                skin: skin,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _label('ENGINE RPM / 回転数', size: 12),
                        const Spacer(),
                        SevenReadout(
                          value: data.rpm.toString(),
                          ghostWidth: 4,
                          fontSize: 26,
                          color: skin.accent,
                          ghostColor: skin.accent.withValues(alpha: 0.08),
                        ),
                        const SizedBox(width: 4),
                        Text('rpm',
                            style: TextStyle(color: skin.dim, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 16,
                      child: _SegmentBar(
                        segments: 40,
                        fill: (data.rpm / 10000).clamp(0.0, 1.0),
                        colorAt: _rpmSegColor,
                        tickColor: skin.faint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _scaleRow(const [0, 2000, 4000, 6000, 8000, 10000]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 巨车速 + 档位
              Expanded(
                child: _Panel(
                  skin: skin,
                  fillAlpha: 0.05,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('VEHICLE SPEED', size: 12),
                      Expanded(
                        child: Center(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                data.speed.toStringAsFixed(0),
                                style: TextStyle(
                                  fontFamily: 'DSEG7',
                                  fontWeight: FontWeight.bold,
                                  fontSize: w * 0.24,
                                  color: skin.accent,
                                  height: 0.9,
                                  shadows: [
                                    Shadow(
                                        color: skin.accent
                                            .withValues(alpha: 0.5),
                                        blurRadius: 24),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: Text('km/h',
                                    style: TextStyle(
                                        color: skin.dim,
                                        fontSize: 15,
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
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 水温
              _Panel(
                skin: skin,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _label('COOLANT TEMP / 水温', size: 12),
                        const Spacer(),
                        SevenReadout(
                          value: (data.coolant == null
                                  ? '--'
                                  : data.coolant!.toStringAsFixed(0))
                              .padLeft(2, ' '),
                          ghostWidth: 2,
                          fontSize: 26,
                          color: _coolantColor() ?? skin.accent,
                          ghostColor: skin.accent.withValues(alpha: 0.08),
                        ),
                        const SizedBox(width: 2),
                        Text('°C', style: TextStyle(color: skin.dim, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 14,
                      child: _SegmentBar(
                        segments: 24,
                        fill: ((data.coolant ?? 0) / 120).clamp(0.0, 1.0),
                        colorAt: _coolSegColor,
                        tickColor: skin.faint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _scaleRow(const [0, 40, 80, 120]),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // FUEL / MILEAGE / 电压
              _Panel(
                skin: skin,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _FuelCard(
                        skin: skin,
                        label: 'FUEL / 燃費',
                        value: data.fuelLph?.toStringAsFixed(1) ??
                            data.fuelL100?.toStringAsFixed(1) ??
                            '--',
                        unit: data.fuelLph != null ? 'L/h' : 'L/100km',
                        vertical: true,
                      ),
                    ),
                    Container(width: 1, color: skin.panelStroke),
                    Expanded(
                      child: _FuelCard(
                        skin: skin,
                        label: 'MILEAGE',
                        value: data.tripKm.toStringAsFixed(1),
                        unit: 'km',
                        vertical: true,
                      ),
                    ),
                    Container(width: 1, color: skin.panelStroke),
                    Expanded(
                      child: _FuelCard(
                        skin: skin,
                        label: 'VOLTAGE / 電圧',
                        value: data.voltage?.toStringAsFixed(1) ?? '--',
                        unit: 'V',
                        vertical: true,
                        valueColor: skin.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _Footer(skin: skin, connected: data.connected && !data.dataLost),
            ],
          ),
        ),
          ],
        ),
      );
    });
  }
}

// ──────────────────────────── 子组件 ────────────────────────────

class _SegStop {
  const _SegStop(this.t, this.c);
  final double t;
  final Color c;
}

/// 分段水平条：按 colorAt 提供的渐变色着色，未点亮段低透明。
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.segments,
    required this.fill,
    required this.colorAt,
    required this.tickColor,
  });

  final int segments;
  final double fill;
  final Color Function(double t) colorAt;
  final Color tickColor;

  @override
  Widget build(BuildContext context) {
    final lit = (fill * segments).round().clamp(0, segments);
    return Row(
      children: List.generate(segments, (i) {
        final t = (i + 0.5) / segments;
        final base = colorAt(t);
        final on = i < lit;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < segments - 1 ? 2.5 : 0),
            decoration: BoxDecoration(
              color: on ? base : base.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        );
      }),
    );
  }
}

/// 琥珀描边面板（切角矩形）。
class _Panel extends StatelessWidget {
  const _Panel({
    required this.skin,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.fillAlpha = 0.16,
  });

  final SkinDescriptor skin;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double fillAlpha;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PanelPainter(skin, fillAlpha),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PanelPainter extends CustomPainter {
  _PanelPainter(this.skin, this.fillAlpha);
  final SkinDescriptor skin;
  final double fillAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 5.0;
    final path = Path();
    // 左上角微切角
    path.moveTo(r, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, r);
    path.close();
    // 内部填充（先填充再描边）
    final fill = Paint()
      ..color = skin.panel.withValues(alpha: fillAlpha);
    canvas.drawPath(path, fill);
    // 描边
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = skin.panelStroke;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _PanelPainter old) =>
      old.skin != skin || old.fillAlpha != fillAlpha;
}

/// NERV 叶片标识（圆 + 斜叶）。
class _NervLeafLogo extends StatelessWidget {
  const _NervLeafLogo({required this.skin, required this.size});
  final SkinDescriptor skin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _NervLeafPainter(skin.accent),
    );
  }
}

class _NervLeafPainter extends CustomPainter {
  _NervLeafPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.42;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.045
      ..color = color;
    // 圆
    canvas.drawCircle(c, r, stroke);
    // 叶片（斜椭圆，自右上向左下）
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 4.2);
    final leaf = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final leafRect = Rect.fromCenter(
        center: const Offset(0, -1),
        width: r * 0.78,
        height: r * 1.75);
    canvas.drawOval(leafRect, leaf);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NervLeafPainter old) => old.color != color;
}

/// 危险斜纹。
class _HazardStripes extends StatelessWidget {
  const _HazardStripes({
    required this.color,
    this.height = 8,
    this.count = 22,
  });
  final Color color;
  final double height;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _StripePainter(color, count),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.color, this.count);
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.85);
    final gap = size.width / count;
    final w = gap * 0.42;
    for (var i = -1; i < count + 1; i++) {
      final x = i * gap;
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + w, size.height)
        ..lineTo(x + w + size.height * 0.9, 0)
        ..lineTo(x + size.height * 0.9, 0)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) =>
      old.color != color || old.count != count;
}

/// 顶部 Header。
class _Header extends StatelessWidget {
  const _Header({required this.skin, this.compact = false});
  final SkinDescriptor skin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 32.0 : 42.0;
    final titleSize = compact ? 15.0 : 20.0;
    final subSize = compact ? 9.0 : 10.5;
    return LayoutBuilder(builder: (context, con) {
      final wide = con.maxWidth > con.maxHeight * 2.4;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _NervLeafLogo(skin: skin, size: logoSize),
          SizedBox(width: compact ? 8 : 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('車両状態診断',
                  style: TextStyle(
                      color: skin.accent,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: 1)),
              SizedBox(height: compact ? 1 : 2),
              Text('VEHICLE DIAGNOSTIC',
                  style: TextStyle(
                      color: skin.dim,
                      fontSize: subSize,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: compact ? 2 : 3),
              SizedBox(
                width: compact ? 120 : 150,
                child: _HazardStripes(
                    color: skin.accent,
                    height: compact ? 5 : 7,
                    count: 18),
              ),
            ],
          ),
          const Spacer(),
          if (wide)
            Text('17:08',
                style: TextStyle(
                  fontFamily: 'DSEG7',
                  color: skin.accent,
                  fontSize: compact ? 20 : 26,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                        color: skin.accent.withValues(alpha: 0.4),
                        blurRadius: 10),
                  ],
                )),
          if (wide) const SizedBox(width: 16),
          if (wide)
            _HeaderButton(
              skin: skin,
              icon: Icons.circle,
              iconColor: skin.ok,
              title: 'DIAGNOSTIC',
              sub: '診断',
            ),
          if (wide) const SizedBox(width: 8),
          if (wide)
            _HeaderButton(
              skin: skin,
              icon: Icons.settings,
              title: 'SETTINGS',
              sub: '設定',
            ),
        ],
      );
    });
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.skin,
    required this.icon,
    required this.title,
    required this.sub,
    this.iconColor,
  });
  final SkinDescriptor skin;
  final IconData icon;
  final String title;
  final String sub;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: skin.panel.withValues(alpha: 0.25),
        border: Border.all(color: skin.panelStroke, width: 1.3),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? skin.accent),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      color: skin.ink,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              Text(sub,
                  style: TextStyle(color: skin.dim, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

/// FUEL / MILEAGE 小卡。
class _FuelCard extends StatelessWidget {
  const _FuelCard({
    required this.skin,
    required this.label,
    required this.value,
    required this.unit,
    this.vertical = false,
    this.valueColor,
  });
  final SkinDescriptor skin;
  final String label;
  final String value;
  final String unit;
  final bool vertical;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: skin.dim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SevenReadout(
              value: value.padLeft(3, ' '),
              ghostWidth: 3,
              fontSize: 28,
              color: valueColor ?? skin.accent,
              ghostColor: skin.accent.withValues(alpha: 0.08),
            ),
            const SizedBox(width: 3),
            Text(unit,
                style: TextStyle(color: skin.dim, fontSize: 11, letterSpacing: 0.5)),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: vertical ? content : FittedBox(fit: BoxFit.scaleDown, child: content),
    );
  }
}

/// 页脚：OBD-II INTERFACE / DATA LINK / SYNC。
class _Footer extends StatelessWidget {
  const _Footer({required this.skin, required this.connected});
  final SkinDescriptor skin;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < c.maxHeight;
      return Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('OBD-II INTERFACE',
                  style: TextStyle(
                      color: skin.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              Text('MODEL: NERV-2000',
                  style: TextStyle(color: skin.dim, fontSize: 9, letterSpacing: 1)),
            ],
          ),
          SizedBox(width: compact ? 8 : 18),
          if (!compact)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('DATA LINK',
                      style: TextStyle(
                          color: skin.dim,
                          fontSize: 8,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: skin.panelStroke.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: connected ? 0.85 : 0.15,
                      child: Container(
                        decoration: BoxDecoration(
                          color: connected ? skin.ok : skin.bad,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!compact) const SizedBox(width: 14),
          Text(connected ? 'SYNC' : 'LOST',
              style: TextStyle(
                  color: connected ? skin.ok : skin.warn,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: _HazardStripes(
                color: connected ? skin.accent : skin.warn,
                height: 8,
                count: 8),
          ),
        ],
      );
    });
  }
}
