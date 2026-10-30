import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/services/sound_service.dart';

/// 边缘告警闪烁：转速逼近红区 / 水温达 danger / 电压过低时，
/// 在屏幕四角闪烁红色角标边框（约 0.5s 周期），并触发一次告警音 + 重触感。
///
/// 与全屏红屏 [DangerOverlay] 互补：这里只做“边角提示”，不遮数据、不抢全屏。
/// 阈值全部取自车型档案（profile.rpmDanger / profile.coolantDanger），
/// 电压过低硬阈值 12.0V（电瓶/充电系统异常）。
///
/// 自动读取 telemetry / skin，可直接 `const AlertFlash()` 放入仪表盘 Stack；
/// 也可传入 [color] 覆盖默认告警色。
class AlertFlash extends ConsumerStatefulWidget {
  const AlertFlash({super.key, this.color});

  /// 覆盖默认告警色（默认取皮肤 bad 色）。
  final Color? color;

  @override
  ConsumerState<AlertFlash> createState() => _AlertFlashState();
}

class _AlertFlashState extends ConsumerState<AlertFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  bool _wasDanger = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 每帧遥测变化都重建：用 listen 保证切换到 danger 时触发告警音。
    final danger = ref.watch(telemetryProvider.select((t) {
      final d = t.current;
      final p = t.profile;
      if (d.rpm >= p.rpmDanger) return true;
      final cool = d.coolant;
      if (cool != null && cool >= p.coolantDanger) return true;
      final v = d.voltage;
      if (v != null && v < 12.0) return true;
      return false;
    }));

    // 上升沿触发一次告警（playAlert 内部已带 2s 节流）。
    if (danger && !_wasDanger) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SoundService.instance.playAlert();
      });
    }
    _wasDanger = danger;

    final skin = ref.watch(skinProvider);
    final color = widget.color ?? skin.bad;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // 闪烁：透明度在 0.25~1.0 间往复
          final opacity = danger ? (0.35 + _c.value * 0.65) : 0.0;
          if (opacity == 0.0) return const SizedBox.shrink();
          return Opacity(
            opacity: opacity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double len = 26; // 角标臂长
                const double th = 4; // 角标线粗
                return Stack(
                  children: [
                    // 左上
                    Positioned(
                      left: 10, top: 10,
                      child: _Corner(len: len, th: th, color: color, flipH: false, flipV: false),
                    ),
                    // 右上
                    Positioned(
                      right: 10, top: 10,
                      child: _Corner(len: len, th: th, color: color, flipH: true, flipV: false),
                    ),
                    // 左下
                    Positioned(
                      left: 10, bottom: 10,
                      child: _Corner(len: len, th: th, color: color, flipH: false, flipV: true),
                    ),
                    // 右下
                    Positioned(
                      right: 10, bottom: 10,
                      child: _Corner(len: len, th: th, color: color, flipH: true, flipV: true),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 单个 L 形角标。
class _Corner extends StatelessWidget {
  const _Corner({
    required this.len,
    required this.th,
    required this.color,
    required this.flipH,
    required this.flipV,
  });

  final double len;
  final double th;
  final Color color;
  final bool flipH;
  final bool flipV;

  @override
  Widget build(BuildContext context) {
    Widget w = SizedBox(
      width: len,
      height: len,
      child: CustomPaint(
        painter: _CornerPainter(len: len, th: th, color: color),
      ),
    );
    if (flipH) w = Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(math.pi), child: w);
    if (flipV) w = Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateX(math.pi), child: w);
    return w;
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.len, required this.th, required this.color});
  final double len;
  final double th;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = th
      ..strokeCap = StrokeCap.round;
    // 横向臂
    canvas.drawLine(Offset(0, 0), Offset(len, 0), paint);
    // 纵向臂
    canvas.drawLine(Offset(0, 0), Offset(0, len), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.color != color || old.len != len || old.th != th;
}
