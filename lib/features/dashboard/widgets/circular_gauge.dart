import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 圆形转速表：270° 弧（135° 起始），刻度 + 红区弧 + 指针 + 中心数字。
/// 复刻原生 CLUSTER 皮肤的 drawRpmGauge。
class CircularRpmGauge extends StatelessWidget {
  const CircularRpmGauge({
    super.key,
    required this.rpm,
    required this.redline,
    required this.maxRpm,
    required this.accent,
    required this.bad,
    required this.dim,
    required this.ink,
    required this.faint,
    this.showText = true,
    this.fontFamily,
  });

  final int rpm;
  final int redline;
  final int maxRpm;
  final Color accent;
  final Color bad;
  final Color dim;
  final Color ink;
  final Color faint;
  final bool showText;
  final String? fontFamily;

  static const _startAngle = 135.0;
  static const _sweepAngle = 270.0;

  static double _rad(double deg) => deg * math.pi / 180.0;

  @override
  Widget build(BuildContext context) {
    // AspectRatio 确保在 Row（高度无界）中也能获得正确尺寸
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _GaugePainter(
          rpm: rpm,
          redline: redline,
          maxRpm: maxRpm,
          accent: accent,
          bad: bad,
          dim: dim,
          ink: ink,
          faint: faint,
          showText: showText,
          fontFamily: fontFamily,
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.rpm,
    required this.redline,
    required this.maxRpm,
    required this.accent,
    required this.bad,
    required this.dim,
    required this.ink,
    required this.faint,
    required this.showText,
    this.fontFamily,
  });

  final int rpm;
  final int redline;
  final int maxRpm;
  final Color accent;
  final Color bad;
  final Color dim;
  final Color ink;
  final Color faint;
  final bool showText;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide / 2;

    // 外圆
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF161920);
    canvas.drawCircle(Offset(cx, cy), r, outerPaint);

    // 刻度（每 200rpm 一小格，每 1000rpm 大格）
    final tickCount = (maxRpm / 1000 * 5).toInt();
    for (var i = 0; i <= tickCount; i++) {
      final v = i / 5 * 1000;
      final deg = CircularRpmGauge._startAngle +
          CircularRpmGauge._sweepAngle * (v / maxRpm);
      final rad = CircularRpmGauge._rad(deg);
      final major = i % 5 == 0;
      final r1 = r * (major ? 0.88 : 0.94);
      final r2 = r;
      final overRed = v >= redline;

      final tickPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = major ? 1.6 : 1.0
        ..color = overRed
            ? bad
            : major
                ? dim
                : const Color(0xFF2A2E38);

      canvas.drawLine(
        Offset(cx + r1 * math.cos(rad), cy + r1 * math.sin(rad)),
        Offset(cx + r2 * math.cos(rad), cy + r2 * math.sin(rad)),
        tickPaint,
      );

      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: (v / 1000).toInt().toString(),
            style: TextStyle(
              color: overRed ? bad : dim,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            cx + r * 0.75 * math.cos(rad) - tp.width / 2,
            cy + r * 0.75 * math.sin(rad) - tp.height / 2,
          ),
        );
      }
    }

    // 红区弧
    final redlineFrac = redline / maxRpm;
    final redStart = CircularRpmGauge._startAngle +
        CircularRpmGauge._sweepAngle * redlineFrac;
    final redPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = bad;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      CircularRpmGauge._rad(redStart),
      CircularRpmGauge._rad(
          CircularRpmGauge._sweepAngle * (1 - redlineFrac)),
      false,
      redPaint,
    );

    // 指针
    final needleFrac = (rpm / maxRpm).clamp(0.0, 1.0);
    final needleDeg = CircularRpmGauge._startAngle +
        CircularRpmGauge._sweepAngle * needleFrac;
    final needleRad = CircularRpmGauge._rad(needleDeg);
    final needlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = accent;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r * 0.86 * math.cos(needleRad),
          cy + r * 0.86 * math.sin(needleRad)),
      needlePaint,
    );

    // 中心圆点
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = accent);
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = const Color(0xFF0A0B0D));

    // 中心数字
    if (showText) {
      final rpmText = (rpm / 1000).toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: rpmText,
              style: TextStyle(
                color: ink,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                fontFamily: fontFamily,
              ),
            ),
            TextSpan(
              text: '\n×1000 RPM',
              style: TextStyle(
                color: faint,
                fontSize: 9,
                fontFamily: fontFamily,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      tp.paint(
        canvas,
        Offset(cx - tp.width / 2, cy + r * 0.20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.rpm != rpm || old.redline != redline;
}
