import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 实时马力估算曲线。
///
/// 自然吸气发动机：HP ≈ MAF(g/s) × 1.2
/// 推导：燃料质量流量 = MAF/14.7，燃料能量 = ×44MJ/kg，
/// 热效率约 30%，换算马力（÷746）→ MAF × 1.20。
/// 马6 2.0L 峰值 MAF 约 120 g/s → 约 144 HP，与原厂标定吻合。
class HorsepowerCurve extends StatefulWidget {
  const HorsepowerCurve({
    super.key,
    required this.data,
    required this.accent,
    required this.dim,
    required this.faint,
  });

  final ObdData data;
  final Color accent;
  final Color dim;
  final Color faint;

  /// 估算当前马力（MAF 法）。
  static double estimate(ObdData data) {
    final maf = data.maf;
    if (maf == null || maf <= 0) return 0;
    return maf * 1.2;
  }

  @override
  State<HorsepowerCurve> createState() => _HorsepowerCurveState();
}

class _HorsepowerCurveState extends State<HorsepowerCurve> {
  // 最近 N 个数据点（HP）
  static const _maxPoints = 120;
  final List<double> _points = [];
  double _peak = 0;

  @override
  void didUpdateWidget(HorsepowerCurve oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hp = HorsepowerCurve.estimate(widget.data);
    _points.add(hp);
    if (_points.length > _maxPoints) _points.removeAt(0);
    if (hp > _peak) _peak = hp;
  }

  @override
  Widget build(BuildContext context) {
    final hp = HorsepowerCurve.estimate(widget.data);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('实时马力估算',
                  style: TextStyle(
                      color: widget.dim,
                      fontSize: 13,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${hp.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                    color: widget.accent,
                  )),
              Text(' HP',
                  style: TextStyle(color: widget.dim, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: CustomPaint(
              size: Size.infinite,
              painter: _CurvePainter(
                points: _points,
                accent: widget.accent,
                faint: widget.faint,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('峰值 ${_peak.toStringAsFixed(0)} HP',
                  style: TextStyle(
                      color: widget.faint, fontSize: 11, letterSpacing: 1)),
              Text('基于 MAF 空气质量流量估算',
                  style: TextStyle(color: widget.faint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.accent,
    required this.faint,
  });

  final List<double> points;
  final Color accent;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final maxHp = math.max(160.0, points.reduce(math.max));

    // 网格线
    final gridPaint = Paint()
      ..color = faint.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 曲线
    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (_HorsepowerCurveState._maxPoints - 1);
      final y = size.height - (points[i] / maxHp) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(
        size.width * (points.length - 1) / (_HorsepowerCurveState._maxPoints - 1),
        size.height);
    fillPath.close();

    // 填充渐变
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.3),
            accent.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    // 曲线
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.points != points;
}
