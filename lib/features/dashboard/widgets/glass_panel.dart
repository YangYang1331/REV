import 'dart:ui';
import 'package:flutter/material.dart';

/// 玻璃面板：克制填充 + 顶部 1px 高光描边 + 柔和投影。
/// 描边比填充更能塑造玻璃边缘；嵌套最多一层。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.fill = const Color(0x0FFFFFFF),
    this.stroke = const Color(0x1FFFFFFF),
    this.topHighlight = const Color(0x22FFFFFF),
    this.blur = 18,
    this.radius = 14,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius,
    this.enableBlur = true,
  });

  final Widget child;
  final Color fill;
  final Color stroke;
  final Color topHighlight;
  final double blur;
  final double radius;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(radius);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        border: Border.all(color: stroke, width: 1),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill, fill.withOpacity(fill.opacity * 0.55)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!enableBlur) return panel;
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Stack(
          children: [
            panel,
            // 顶部 1px 高光
            Positioned(
              left: 1,
              right: 1,
              top: 1,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: topHighlight,
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 六边形描边裁切（NERV 用）—— 用 Paint 画带切角的六边形面板。
class HexPanel extends StatelessWidget {
  const HexPanel({
    super.key,
    required this.child,
    this.stroke = const Color(0xFFB8181E),
    this.fill = const Color(0x14FF2A24),
    this.padding = const EdgeInsets.all(12),
    this.cut = 14,
  });
  final Widget child;
  final Color stroke;
  final Color fill;
  final EdgeInsets padding;
  final double cut;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HexPanelPainter(stroke, fill, cut),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _HexPanelPainter extends CustomPainter {
  _HexPanelPainter(this.stroke, this.fill, this.cut);
  final Color stroke;
  final Color fill;
  final double cut;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    // 左上、右上切角
    path.moveTo(cut, 0);
    path.lineTo(size.width - cut, 0);
    path.lineTo(size.width, cut);
    path.lineTo(size.width, size.height - cut);
    path.lineTo(size.width - cut, size.height);
    path.lineTo(cut, size.height);
    path.lineTo(0, size.height - cut);
    path.lineTo(0, cut);
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = stroke
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(covariant _HexPanelPainter old) =>
      old.stroke != stroke || old.fill != fill;
}
