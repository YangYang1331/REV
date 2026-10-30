import 'dart:math' as math;
import 'package:flutter/material.dart';

/// REV 品牌标识：圆形仪表图标（白弧→红弧 + 红指针，对齐应用启动器）+ 名称。
/// 用于替换皮肤背景图里烘焙的第三方 logo（如山转皮肤的「山轉」）。
class RevBrandLogo extends StatelessWidget {
  const RevBrandLogo({
    super.key,
    this.size = 44,
    this.color = const Color(0xFFFFFFFF),
    this.accent = const Color(0xFFFF2A2A),
    this.titleColor = const Color(0xFFFFFFFF),
    this.showTitle = true,
    this.subtitle = 'OBD',
    this.onDarkPlate = false,
  });

  /// 仪表图标边长（正方形）。
  final double size;
  final Color color;
  final Color accent;
  final Color titleColor;
  final bool showTitle;
  final String? subtitle;

  /// 是否需要黑色底板（用于覆盖背景图里已烘焙的旧 logo）。
  final bool onDarkPlate;

  @override
  Widget build(BuildContext context) {
    final plate = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.08),
        child: _GaugeMark(size: size, color: color, accent: accent),
      ),
    );

    if (!showTitle) {
      return onDarkPlate ? plate : _GaugeMark(size: size, color: color, accent: accent);
    }

    final base = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        onDarkPlate
            ? plate
            : _GaugeMark(size: size, color: color, accent: accent),
        SizedBox(width: size * 0.22),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REV',
              style: TextStyle(
                color: titleColor,
                fontSize: size * 0.56,
                fontWeight: FontWeight.w900,
                height: 0.95,
                letterSpacing: size * 0.04,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  color: titleColor.withValues(alpha: 0.55),
                  fontSize: size * 0.19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: size * 0.12,
                ),
              ),
          ],
        ),
      ],
    );

    if (!onDarkPlate) return base;
    // 黑色底板横向铺满，完全盖住背景图里的旧 logo
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF050505)),
      padding: EdgeInsets.symmetric(
          horizontal: size * 0.28, vertical: size * 0.16),
      child: base,
    );
  }
}

/// 纯代码绘制的圆形仪表标识（复刻启动器图标）。
class _GaugeMark extends StatelessWidget {
  const _GaugeMark({
    required this.size,
    required this.color,
    required this.accent,
  });

  final double size;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GaugeMarkPainter(color: color, accent: accent),
    );
  }
}

class _GaugeMarkPainter extends CustomPainter {
  _GaugeMarkPainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.44;

    // 外圈 270° 弧（从 135° 起）：白→红渐变
    const start = 135.0;
    const sweep = 270.0;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _rad(start),
        endAngle: _rad(start + sweep),
        colors: [
          color,
          color.withValues(alpha: 0.95),
          accent.withValues(alpha: 0.2),
          accent,
        ],
        stops: const [0.0, 0.45, 0.7, 1.0],
        transform: GradientRotation(_rad(start)),
      ).createShader(rect);
    canvas.drawArc(rect, _rad(start), _rad(sweep), false, paint);

    // 刻度（小细线）
    final tickPaint = Paint()
      ..strokeWidth = size.width * 0.018
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 12; i++) {
      final a = _rad(start + sweep * i / 12);
      final inRed = i >= 9;
      tickPaint.color =
          (inRed ? accent : color).withValues(alpha: inRed ? 0.9 : 0.5);
      final p1 = c +
          Offset(math.cos(a), math.sin(a)) * (r - size.width * 0.13);
      final p2 = c +
          Offset(math.cos(a), math.sin(a)) * (r - size.width * 0.20);
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 指针（指向约 60% 处，落在红区前）
    final needleAngle = _rad(start + sweep * 0.72);
    final needlePaint = Paint()
      ..color = accent
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c,
      c +
          Offset(math.cos(needleAngle), math.sin(needleAngle)) *
              (r - size.width * 0.18),
      needlePaint,
    );

    // 中心轴
    final hub = Paint()..color = const Color(0xFF222222);
    final hubR = size.width * 0.085;
    canvas.drawCircle(c, hubR, hub);
    canvas.drawCircle(
        c,
        hubR,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.02);
  }

  double _rad(double deg) => deg * math.pi / 180.0;

  @override
  bool shouldRepaint(covariant _GaugeMarkPainter old) =>
      old.color != color || old.accent != accent;
}
