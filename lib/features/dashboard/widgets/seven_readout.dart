import 'package:flutter/material.dart';

/// DSEG 七段数码管读数：幽灵位 + 真实值，数值变化时上下滚动切换。
/// 静态渲染与原版完全一致；仅在 value 变化时触发 220ms 滚动动画。
class SevenReadout extends StatelessWidget {
  const SevenReadout({
    super.key,
    required this.value,
    this.unit,
    this.digits = 3,
    this.ghostWidth,
    this.fontSize = 96,
    this.color = Colors.white,
    this.ghostColor,
    this.fontFamily = 'DSEG7',
    this.unitFontSize,
  });

  final String value;
  final String? unit;
  final int digits;
  final int? ghostWidth;
  final double fontSize;
  final Color color;
  final Color? ghostColor;
  final String fontFamily;
  final double? unitFontSize;

  @override
  Widget build(BuildContext context) {
    final str = value;
    final digitStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      height: 1.0,
      letterSpacing: 0,
    );
    final ghost = ghostColor ?? color.withValues(alpha: 0.12);
    // 单位一律用系统 UI 字体：DSEG7 是七段数码管，只能渲染数字与极少数符号，
    // 把 °C / bar / g/s / L/100km / km/h 等单位交给它会显示成方块/错字。
    final unitStyle = TextStyle(
      fontSize: unitFontSize ?? fontSize * 0.28,
      color: color.withValues(alpha: 0.6),
      height: 1.0,
      fontWeight: FontWeight.w600,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Stack(
          children: [
            Text(
              '8' * (ghostWidth ?? digits),
              style: digitStyle.copyWith(color: ghost),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Text(
                str,
                key: ValueKey(str),
                style: digitStyle,
              ),
            ),
          ],
        ),
        if (unit != null) ...[
          const SizedBox(width: 6),
          Text(unit!, style: unitStyle),
        ],
      ],
    );
  }
}
