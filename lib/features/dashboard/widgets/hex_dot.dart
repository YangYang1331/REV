import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 六边形面板：水平六边形描边（flat-top 或 pointy-top）。
/// 复刻原生 CYAN_HEX 的 drawHex。
class HexPanel extends StatelessWidget {
  const HexPanel({
    super.key,
    required this.color,
    this.fill = false,
    this.strokeWidth = 1.5,
    this.child,
  });

  final Color color;
  final bool fill;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HexPainter(
        color: color,
        fill: fill,
        strokeWidth: strokeWidth,
      ),
      child: SizedBox.expand(child: child),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter({
    required this.color,
    required this.fill,
    required this.strokeWidth,
  });

  final Color color;
  final bool fill;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = math.min(w / 2, h / math.sqrt(3));

    // pointy-top 六边形（顶点在上下）
    final points = List.generate(6, (i) {
      final angle = math.pi / 3 * i - math.pi / 6;
      return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
    });

    final path = Path()..addPolygon(points, true);

    if (fill) {
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.08));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) =>
      old.color != color || old.fill != fill;
}

/// 点阵档位：用 LED 点阵风格显示大档位字符。
/// 复刻原生 drawDotGear（5x7 点阵）。
class DotGear extends StatelessWidget {
  const DotGear({
    super.key,
    required this.gear,
    required this.color,
    this.size = 48,
  });

  final String gear;
  final Color color;
  final double size;

  // 5列 x 7行 点阵字体（N, 1-8, -）
  static const Map<String, List<String>> _glyphs = {
    'N': [
      '1...1',
      '11..1',
      '1.1.1',
      '1..11',
      '1...1',
      '1...1',
      '1...1',
    ],
    '1': [
      '..1..',
      '.11..',
      '..1..',
      '..1..',
      '..1..',
      '..1..',
      '.111.',
    ],
    '2': [
      '.111.',
      '1...1',
      '....1',
      '..11.',
      '.1...',
      '1....',
      '11111',
    ],
    '3': [
      '.111.',
      '1...1',
      '....1',
      '..11.',
      '....1',
      '1...1',
      '.111.',
    ],
    '4': [
      '...1.',
      '..11.',
      '.1.1.',
      '1..1.',
      '11111',
      '...1.',
      '...1.',
    ],
    '5': [
      '11111',
      '1....',
      '1111.',
      '....1',
      '....1',
      '1...1',
      '.111.',
    ],
    '6': [
      '.111.',
      '1....',
      '1....',
      '1111.',
      '1...1',
      '1...1',
      '.111.',
    ],
    '7': [
      '11111',
      '....1',
      '...1.',
      '..1..',
      '.1...',
      '.1...',
      '.1...',
    ],
    '8': [
      '.111.',
      '1...1',
      '1...1',
      '.111.',
      '1...1',
      '1...1',
      '.111.',
    ],
    '-': [
      '.....',
      '.....',
      '.....',
      '11111',
      '.....',
      '.....',
      '.....',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final glyph = _glyphs[gear] ?? _glyphs['-']!;
    final dotSize = size / 8;
    final gap = dotSize * 0.25;

    return SizedBox(
      width: 5 * dotSize + 4 * gap,
      height: 7 * dotSize + 6 * gap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(7, (row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (col) {
              final lit = glyph[row][col] == '1';
              return Container(
                width: dotSize,
                height: dotSize,
                margin: EdgeInsets.only(
                  right: col < 4 ? gap : 0,
                  bottom: row < 6 ? gap : 0,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lit
                      ? color
                      : color.withValues(alpha: 0.12),
                  boxShadow: lit
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: dotSize * 0.6,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          );
        }),
      ),
    );
  }
}
