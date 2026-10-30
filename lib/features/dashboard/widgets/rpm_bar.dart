import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';

/// 分段转速条。横 / 竖两向，带警告色段（红区）。
class RpmBar extends StatelessWidget {
  const RpmBar({
    super.key,
    required this.rpm,
    required this.redline,
    required this.skin,
    required this.axis,
    this.segments = 20,
    this.gap = 3,
    this.thickness = 12,
    this.maxRpm,
    this.activeColor,
  });

  final int rpm;
  final int redline;
  final SkinDescriptor skin;
  final Axis axis;
  final int segments;
  final double gap;
  final double thickness;

  /// 刻度 / 填充上限；为空时按 redline 归一化（原行为）。
  /// 当需要 0–10000 刻度而 redline 仅 6500 时传入，使填充与刻度对齐，
  /// 红区仍从 redline 位置开始。
  final int? maxRpm;

  /// 正常区填充色；为空时用 skin.accent。NERV 复刻原版传琥珀色。
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final scaleMax = (maxRpm ?? redline).toDouble();
    final lit = (rpm / scaleMax * segments).round().clamp(0, segments);
    final warnStart = maxRpm == null
        ? (segments * 0.85).round()
        : (redline / scaleMax * segments).round();
    final normal = activeColor ?? skin.accent;
    final cells = List.generate(segments, (i) {
      final on = i < lit;
      Color c = skin.faint;
      if (on) {
        c = i >= warnStart
            ? skin.bad
            : (i >= warnStart - 3 ? skin.warn : normal);
      }
      return Expanded(child: Container(margin: edge(i), color: on ? c : c.withOpacity(0.18)));
    });
    return SizedBox(
      height: axis == Axis.horizontal ? thickness : double.infinity,
      width: axis == Axis.vertical ? thickness : double.infinity,
      child: axis == Axis.horizontal
          ? Row(children: cells)
          : Column(verticalDirection: VerticalDirection.up, children: cells),
    );
  }

  EdgeInsets edge(int i) =>
      axis == Axis.horizontal ? EdgeInsets.only(right: i < segments - 1 ? gap : 0)
      : EdgeInsets.only(top: i < segments - 1 ? gap : 0);
}

/// 水墨笔触式转速条（Touge 用）：连续填充 + 粗砺端尾，非分段。
class BrushRpmBar extends StatelessWidget {
  const BrushRpmBar({
    super.key,
    required this.rpm,
    required this.redline,
    required this.color,
    this.height = 10,
  });
  final int rpm;
  final int redline;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final frac = (rpm / redline).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      return Stack(
        children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(height),
            ),
          ),
          FractionallySizedBox(
            widthFactor: frac,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.55), color],
                ),
                borderRadius: BorderRadius.circular(height),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12)],
              ),
            ),
          ),
        ],
      );
    });
  }
}
