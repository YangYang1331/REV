import 'package:flutter/material.dart';

/// 档位数码管：N / R / 1..N，DSEG 七段。
class GearWidget extends StatelessWidget {
  const GearWidget({
    super.key,
    required this.gear,
    required this.color,
    this.ghostColor,
    this.fontSize = 96,
  });
  final int gear;
  final Color color;
  final Color? ghostColor;
  final double fontSize;

  String get _letter {
    if (gear < 0) return '-';
    if (gear == 0) return 'N';
    return '$gear';
  }

  @override
  Widget build(BuildContext context) {
    final ghost = ghostColor ?? color.withValues(alpha: 0.10);
    final style = TextStyle(
      fontFamily: 'DSEG7',
      fontWeight: FontWeight.bold,
      fontSize: fontSize,
      height: 1.0,
    );
    return SizedBox(
      width: fontSize * 0.78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('8', style: style.copyWith(color: ghost)),
          Text(_letter, style: style.copyWith(color: color)),
        ],
      ),
    );
  }
}
