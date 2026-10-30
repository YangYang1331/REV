import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/store/app_store.dart';

/// 地平线（Forza Horizon）风共享组件：
///  - [HorizonWarningType] + [paintWarningIcon]：自绘描边警示灯图标（安全带/机油/电瓶/
///    ABS/发动机故障/驻车P/远光），无网络图/emoji，开屏与十皮肤 overlay 复用。
///  - [RoundGaugePainter]：副圆形仪表（车速/水温/油表）自检扫表。
///  - [HorizonFxOverlay]：进仪表盘页面时一次性播放的克制入场动效（背光+警示灯+光扫），
///    播完即完全透明，不改变皮肤布局/配色/数据。总开关 [AppStore.horizonFx]。
///
/// 性能：单 CustomPaint、无 saveLayer、无重模糊，粒子为 0，2GB/API25 车机可 60fps。

/// 警示灯类型（顺序即一排排列顺序）。
enum HorizonWarning { seatbelt, abs, oil, battery, checkEngine, parking, highBeam }

/// 每盏警示灯默认颜色：信息类用青，告警类用琥珀，符合真车仪表惯例。
Color horizonWarningColor(HorizonWarning w) {
  switch (w) {
    case HorizonWarning.seatbelt:
    case HorizonWarning.parking:
    case HorizonWarning.highBeam:
      return const Color(0xFF27D6E6); // cyan
    case HorizonWarning.abs:
    case HorizonWarning.oil:
    case HorizonWarning.battery:
      return const Color(0xFFFFB02E); // amber
    case HorizonWarning.checkEngine:
      return const Color(0xFFFF6A3D); // red-amber
  }
}

/// 在 [rect] 内居中绘制一盏描边警示灯图标；[on] 0..1 控制点亮程度（暗→亮+辉光）。
/// 纯矢量描边，统一线宽，不依赖任何图片资源。
void paintWarningIcon(
  Canvas canvas,
  HorizonWarning w,
  Rect rect,
  Color base,
  double on,
) {
  if (on <= 0.01) return;
  canvas.save();
  canvas.clipRect(rect);
  final c = rect.center;
  final s = rect.shortestSide;
  final stroke = s * 0.07;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = base.withOpacity(on)
    ..maskFilter = on > 0.5
        ? MaskFilter.blur(BlurStyle.normal, 1.5 * on)
        : null;

  void line(Offset a, Offset b) => canvas.drawLine(a, b, paint);
  void circle(double r, {bool fill = false}) => canvas.drawCircle(
      c, r, Paint()
        ..color = base.withOpacity(on)
        ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = stroke);

  switch (w) {
    case HorizonWarning.seatbelt:
      // 圆圈 + 斜向安全带（fh4 右侧青色座带图标）
      circle(s * 0.32);
      line(c.translate(-s * 0.20, -s * 0.26), c.translate(s * 0.22, s * 0.28));
      break;
    case HorizonWarning.abs:
      // 圆角方框 + ABS 字样（不发光时也只画框，点亮后字亮起）
      final rrect = RRect.fromRectAndRadius(
          rect.deflate(s * 0.10), Radius.circular(s * 0.08));
      canvas.drawRRect(rrect, paint);
      if (on > 0.4) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'ABS',
            style: TextStyle(
              color: base.withOpacity(on),
              fontSize: s * 0.20,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c.translate(-tp.width / 2, -tp.height / 2));
      }
      break;
    case HorizonWarning.oil:
      // 油滴
      final p = Path()
        ..moveTo(c.dx, c.dy - s * 0.30)
        ..quadraticBezierTo(c.dx + s * 0.26, c.dy, c.dx, c.dy + s * 0.28)
        ..quadraticBezierTo(c.dx - s * 0.26, c.dy, c.dx, c.dy - s * 0.30);
      canvas.drawPath(p, paint);
      break;
    case HorizonWarning.battery:
      final bw = s * 0.38, bh = s * 0.26;
      canvas.drawRect(
          Rect.fromCenter(center: c, width: bw, height: bh), paint);
      // 右极柱
      line(c.translate(bw / 2, 0), c.translate(bw / 2 + s * 0.08, 0));
      // 左 +
      line(c.translate(-bw * 0.20, 0), c.translate(-bw * 0.06, 0));
      line(c.translate(-bw * 0.13, -s * 0.05),
          c.translate(-bw * 0.13, s * 0.05));
      // 右 -
      line(c.translate(bw * 0.06, 0), c.translate(bw * 0.20, 0));
      break;
    case HorizonWarning.checkEngine:
      // 简化发动机轮廓：圆角块 + 中缝
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: c, width: s * 0.46, height: s * 0.30),
              Radius.circular(s * 0.06)),
          paint);
      for (var i = -1; i <= 1; i++) {
        line(c.translate(i * s * 0.12, -s * 0.15),
            c.translate(i * s * 0.12, -s * 0.26));
      }
      break;
    case HorizonWarning.parking:
      circle(s * 0.32);
      final tp = TextPainter(
        text: TextSpan(
          text: 'P',
          style: TextStyle(
            color: base.withOpacity(on),
            fontSize: s * 0.30,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c.translate(-tp.width / 2, -tp.height / 2));
      break;
    case HorizonWarning.highBeam:
      // 灯圆 + 向右光束
      canvas.drawCircle(c.translate(-s * 0.12, 0), s * 0.16, paint);
      for (var i = 0; i < 3; i++) {
        final y = (i - 1) * s * 0.13;
        line(c.translate(s * 0.08, y), c.translate(s * 0.30, y));
      }
      break;
  }
  canvas.restore();
}

/// 副圆形仪表（车速/水温/油表）：青色背光弧 + 刻度 + 自检指针 [p]（0..1）。
/// [accent] 背光主色；[label] 中央小字。
class RoundGaugePainter extends CustomPainter {
  RoundGaugePainter({
    required this.p,
    required this.backlight,
    required this.label,
    this.accent = const Color(0xFF27D6E6),
  });
  final double p; // 0..1 指针位置
  final double backlight; // 0..1 背光亮度
  final String label;
  final Color accent;

  static const double _startA = 135 * math.pi / 180;
  static const double _spanA = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    if (W <= 0) return;
    final c = Offset(W / 2, W / 2);
    final r = W * 0.40;
    final arcRect = Rect.fromCircle(center: c, radius: r);

    // 底盘
    canvas.drawCircle(
      c,
      W * 0.48,
      Paint()..color = const Color(0xFF071018).withOpacity(0.92),
    );
    canvas.drawCircle(
      c,
      W * 0.48,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withOpacity(0.12),
    );

    // 暗刻度弧（始终在，背光点亮时更亮）
    canvas.drawArc(
      arcRect,
      _startA,
      _spanA,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = W * 0.035
        ..strokeCap = StrokeCap.round
        ..color = accent.withOpacity(0.10 + 0.25 * backlight),
    );
    // 自检扫亮弧
    if (p > 0) {
      canvas.drawArc(
        arcRect,
        _startA,
        _spanA * p,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = W * 0.038
          ..strokeCap = StrokeCap.round
          ..color = accent.withOpacity(0.35 + 0.6 * backlight)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * backlight),
      );
    }
    // 刻度点
    for (var i = 0; i <= 10; i++) {
      final a = _startA + _spanA * i / 10;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawCircle(c + d * (r + W * 0.05), W * 0.006,
          Paint()..color = Colors.white.withOpacity(0.25 + 0.5 * backlight));
    }
    // 指针
    final angle = _startA + _spanA * p;
    final dir = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      c - dir * W * 0.05,
      c + dir * r,
      Paint()
        ..color = Colors.white
        ..strokeWidth = W * 0.012
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, W * 0.03, Paint()..color = Colors.white);

    // 中央标签
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.55 + 0.4 * backlight),
          fontSize: W * 0.11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c.translate(-tp.width / 2, W * 0.16));
  }

  @override
  bool shouldRepaint(RoundGaugePainter old) =>
      old.p != p || old.backlight != backlight || old.label != label;
}

/// 进仪表盘页面时一次性播放的地平线入场动效：
/// 青/皮肤主色背光淡入淡出 + 一道斜向光扫过面板 + 底部一排警示灯逐亮后熄灭。
/// 播完（controller 完成）即完全透明，不改变皮肤任何布局/配色/数据位置。
/// 总开关 [AppStore.horizonFx]：关闭时直接透传 child，零开销。
class HorizonFxOverlay extends StatefulWidget {
  const HorizonFxOverlay({
    super.key,
    required this.child,
    required this.accent,
  });
  final Widget child;
  final Color accent;

  @override
  State<HorizonFxOverlay> createState() => _HorizonFxOverlayState();
}

class _HorizonFxOverlayState extends State<HorizonFxOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _enabled = AppStore.horizonFx;
    if (_enabled) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) =>
                  CustomPaint(painter: _HorizonOverlayPainter(_c.value, widget.accent)),
            ),
          ),
        ),
      ],
    );
  }
}

/// overlay 入场：t 0..1。
///  - 0.0–0.45 背光径向辉光淡入；
///  - 0.15–0.85 斜向光带从左到右扫过；
///  - 0.25–0.9 底部一排 7 盏警示灯逐盏点亮，随后整体淡出。
class _HorizonOverlayPainter extends CustomPainter {
  _HorizonOverlayPainter(this.t, this.accent);
  final double t;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1.0) return;
    // 整体淡出尾段
    final fadeOut = t > 0.7 ? (1 - (t - 0.7) / 0.3) : 1.0;

    // 1) 背光径向辉光（左上起，克制）
    final glowIn = (t / 0.45).clamp(0.0, 1.0);
    final glowA = 0.16 * glowIn * fadeOut;
    if (glowA > 0.01) {
      final center = Offset(size.width * 0.5, size.height * 0.4);
      final r = size.shortestSide * 0.8;
      final sh = RadialGradient(
        colors: [
          accent.withOpacity(glowA),
          accent.withOpacity(glowA * 0.3),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawRect(Offset.zero & size, Paint()..shader = sh);
    }

    // 2) 斜向光带扫过
    if (t > 0.15 && t < 0.85) {
      final p = ((t - 0.15) / 0.7).clamp(0.0, 1.0);
      final x = -size.width * 0.3 + p * size.width * 1.6;
      final band = Rect.fromLTWH(x - size.width * 0.12, 0,
          size.width * 0.24, size.height);
      final sh = const LinearGradient(
        colors: [Colors.transparent, Colors.white, Colors.transparent],
        stops: [0.0, 0.5, 1.0],
      ).createShader(band);
      canvas.drawRect(
        band,
          Paint()..shader = sh..color = Colors.white.withOpacity(0.05 * fadeOut),
      );
    }

    // 3) 底部警示灯一排逐盏点亮
    if (t > 0.25 && t < 0.95) {
      const icons = HorizonWarning.values;
      final n = icons.length;
      final bw = size.width / n;
      final boxSize = size.shortestSide * 0.055;
      final y = size.height - boxSize - size.height * 0.02;
      for (var i = 0; i < n; i++) {
        // 每盏灯在 0.25 + i*0.05 起点亮，峰值 0.18s，随后整体 fadeOut
        final lit =
            ((t - (0.25 + i * 0.05)) / 0.18).clamp(0.0, 1.0).toDouble();
        if (lit <= 0) continue;
        final on = lit * fadeOut;
        final rect = Rect.fromCenter(
          center: Offset(bw * (i + 0.5), y + boxSize / 2),
          width: boxSize,
          height: boxSize,
        );
        paintWarningIcon(canvas, icons[i], rect, horizonWarningColor(icons[i]), on);
      }
    }
  }

  @override
  bool shouldRepaint(_HorizonOverlayPainter old) =>
      old.t != t || old.accent != accent;
}
