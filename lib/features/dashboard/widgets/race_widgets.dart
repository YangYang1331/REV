import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/features/dashboard/widgets/rpm_bar.dart';

/// ─────────────────────────────────────────────────────────────
/// 赛车化通用组件：换挡灯条 / 分段温度条 / 带刻度转速条 / 切角面板。
/// 参考 Haltech iC-7、MoTeC C1212 等专业赛车仪表的视觉语言：
/// 换挡灯由两侧向中央递进点亮、温度分段条按色带分级、面板硬切角。
/// 全部纯代码绘制，不依赖背景图，横竖屏都能对齐。
/// ─────────────────────────────────────────────────────────────

const _kGreen = Color(0xFF27E08A);
const _kAmber = Color(0xFFFFB020);
const _kRed = Color(0xFFFF2A30);
const _kCyan = Color(0xFF35E0E6);

/// 顶部换挡灯条：奇数颗灯，从两侧向中央递进点亮。
/// 外侧绿（提示）→ 中段琥珀（逼近）→ 中央红（换挡），进入红区后全红闪烁。
class ShiftLightBar extends StatelessWidget {
  const ShiftLightBar({
    super.key,
    required this.rpm,
    required this.redline,
    this.rpmDanger,
    this.count = 15,
    this.height = 16,
    this.gap = 4,
    this.startFraction = 0.55,
    this.alarm = false,
  });

  final int rpm;
  final int redline;
  final int? rpmDanger;
  final int count;
  final double height;
  final double gap;
  final double startFraction;

  /// 告警模式：水温过高/电压过低时，全部灯变红闪烁（AIM/MoTeC 专业仪表做法）。
  final bool alarm;

  @override
  Widget build(BuildContext context) {
    final danger = rpmDanger ?? (redline * 0.985).round();
    final overRed = rpm >= danger;
    final center = count ~/ 2;
    final maxDist = center; // 最外侧灯到中央的距离
    final frac = (rpm / redline).clamp(0.0, 1.1);

    return LayoutBuilder(builder: (context, c) {
      // 红区闪烁 / 告警闪烁（用时间驱动透明度）
      return _Blink(
        blink: overRed || alarm,
        builder: (ctx, blinkOn) {
          final cells = List.generate(count, (i) {
            final dist = (i - center).abs();
            // 越靠外侧阈值越低，越早亮
            final nd = maxDist == 0 ? 0.0 : dist / maxDist; // 0 中央, 1 最外
            final threshold = startFraction + (1 - nd) * (1 - startFraction);
            final lit = alarm || overRed || frac >= threshold;

            Color color;
            if (alarm) {
              color = blinkOn ? _kRed : _kRed.withValues(alpha: 0.25);
            } else if (overRed) {
              color = blinkOn ? _kRed : _kRed.withValues(alpha: 0.25);
            } else if (dist <= 1) {
              color = _kRed; // 中央三颗：红
            } else if (dist <= 4) {
              color = _kAmber; // 中段：琥珀
            } else {
              color = _kGreen; // 外侧：绿
            }
            // 未点亮：极暗描边
            final boxColor = lit ? color : color.withValues(alpha: 0.10);
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(
                    right: i < count - 1 ? gap : 0),
                height: height,
                decoration: BoxDecoration(
                  color: boxColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: lit
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.65),
                            blurRadius: overRed ? 14 : 8,
                          )
                        ]
                      : null,
                  border: Border.all(
                    color: color.withValues(alpha: lit ? 0.9 : 0.18),
                    width: 0.8,
                  ),
                ),
              ),
            );
          });
          return Row(children: cells);
        },
      );
    });
  }
}

/// 红区闪烁驱动：不依赖外部动画，用内部 periodic tick 改透明度。
class _Blink extends StatefulWidget {
  const _Blink({required this.blink, required this.builder});
  final bool blink;
  final Widget Function(BuildContext context, bool on) builder;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..repeat(reverse: true);

  @override
  Widget build(BuildContext context) {
    if (!widget.blink) {
      return widget.builder(context, true);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(context, _c.value > 0.5),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// 分段温度条：冷青 → 正常 → 暖黄 → 热橙 → 危险红，带 0/40/80/120 刻度。
/// 复刻原版 NERV 水温条，同时用于油温。
class TempGaugeBar extends StatelessWidget {
  const TempGaugeBar({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 120,
    this.warn = 105,
    this.danger = 115,
    this.segments = 24,
    this.height = 14,
    this.gap = 2,
    this.showScale = true,
  });

  final double? value;
  final double min;
  final double max;
  final double warn;
  final double danger;
  final int segments;
  final double height;
  final double gap;
  final bool showScale;

  Color _bandColor(double segStart, double segEnd) {
    // 段中点所处区间
    final mid = (segStart + segEnd) / 2;
    if (mid >= danger) return _kRed;
    if (mid >= warn) return _kAmber;
    if (mid >= warn - 12) return const Color(0xFFFFD24A);
    if (mid >= 55) return const Color(0xFF4BE3A0);
    if (mid >= 35) return _kCyan;
    return const Color(0xFF2A8FB0);
  }

  @override
  Widget build(BuildContext context) {
    final v = value ?? min;
    final lit = ((v - min) / (max - min) * segments)
        .round()
        .clamp(0, segments);
    final ticks = [0, 40, 80, 120];

    final cells = List.generate(segments, (i) {
      final segMin = min + i * (max - min) / segments;
      final segMax = min + (i + 1) * (max - min) / segments;
      final on = i < lit;
      final base = _bandColor(segMin, segMax);
      return Expanded(
        child: Container(
          margin: EdgeInsets.only(right: i < segments - 1 ? gap : 0),
          height: height,
          decoration: BoxDecoration(
            color: on ? base : base.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: cells),
        if (showScale) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ticks
                .map((t) => Text(
                      '$t',
                      style: const TextStyle(
                        color: Color(0x99FF7A5A),
                        fontFamily: 'DSEG7',
                        fontSize: 10,
                      ),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

/// 带刻度数字的分段转速条：RpmBar 正下方一排 0 / 2000 / 4000 … 刻度。
class RpmScaleBar extends StatelessWidget {
  const RpmScaleBar({
    super.key,
    required this.rpm,
    required this.redline,
    required this.skin,
    this.segments = 18,
    this.thickness = 12,
    this.maxScaleRpm,
    this.scaleStep = 2000,
    this.activeColor,
  });

  final int rpm;
  final int redline;
  final SkinDescriptor skin;
  final int segments;
  final double thickness;
  final int? maxScaleRpm;
  final int scaleStep;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    // 刻度上限：未显式指定时取红区之上第一个 scaleStep 整倍数
    final top = maxScaleRpm ??
        ((redline ~/ scaleStep) + 1) * scaleStep;
    final ticks = <int>[];
    for (var t = 0; t <= top; t += scaleStep) {
      ticks.add(t);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RpmBar(
          rpm: rpm,
          redline: redline,
          skin: skin,
          axis: Axis.horizontal,
          segments: segments,
          thickness: thickness,
          maxRpm: top,
          activeColor: activeColor,
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ticks
              .map((t) => Text(
                    t == 0 ? '0' : '${t ~/ 1000}000',
                    style: TextStyle(
                      color: skin.faint,
                      fontFamily: 'DSEG7',
                      fontSize: 10,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

/// 硬切角（六边形风格）描边面板，用 CustomPainter 绘制，复刻背景图里的
/// 六边形面板，使新皮肤不依赖背景图也能工整对齐。
class BezelPanel extends StatelessWidget {
  const BezelPanel({
    super.key,
    required this.child,
    required this.stroke,
    this.fill = const Color(0x14000000),
    this.corner = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.glow = false,
  });

  final Widget child;
  final Color stroke;
  final Color fill;
  final double corner;
  final EdgeInsetsGeometry padding;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BezelPainter(
        stroke: stroke,
        fill: fill,
        corner: corner,
        glow: glow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BezelPainter extends CustomPainter {
  _BezelPainter({
    required this.stroke,
    required this.fill,
    required this.corner,
    required this.glow,
  });
  final Color stroke;
  final Color fill;
  final double corner;
  final bool glow;

  Path _bezel(Size s, double c) {
    // 左上、右下做斜切角，其余直角，形成 NERV 硬朗面板。
    return Path()
      ..moveTo(c, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height - c)
      ..lineTo(s.width - c, s.height)
      ..lineTo(0, s.height)
      ..lineTo(0, c)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _bezel(size, corner);
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    canvas.drawPath(p, fillPaint);
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.miter;
    if (glow) {
      strokePaint.maskFilter =
          MaskFilter.blur(BlurStyle.outer, math.min(6, corner * 0.4));
    }
    canvas.drawPath(p, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _BezelPainter old) =>
      old.stroke != stroke ||
      old.fill != fill ||
      old.corner != corner ||
      old.glow != glow;
}
