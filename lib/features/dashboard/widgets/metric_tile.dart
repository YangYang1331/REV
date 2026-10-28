import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/features/dashboard/widgets/seven_readout.dart';

/// 单个数据项：上方小标签 + 下方 DSEG 数码管数值 + 单位。
/// null（不支持/无数据）时显示 “--”，配合支持度分级在实车优雅降级。
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.skin,
    this.digits = 1,
    this.fontSize = 30,
    this.valueColor,
    this.compact = false,
  });

  final String label;
  final double? value;
  final String unit;
  final SkinDescriptor skin;
  final int digits;
  final double fontSize;
  final Color? valueColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final has = value != null;
    final text = !has
        ? '--'
        : value! >= 100
            ? value!.toStringAsFixed(0)
            : value!.toStringAsFixed(digits);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: skin.dim,
            fontSize: compact ? 11 : 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        // 数值+单位整行等比缩放：仅在行宽超出磁贴内容宽度时缩小，
        // 正常态 scale=1.0 渲染与原来完全一致，避免被 GlassPanel 的 ClipRRect 裁掉。
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SevenReadout(
                value: text.padLeft(digits + 2, ' '),
                ghostWidth: digits + 2,
                fontSize: fontSize,
                color: has ? (valueColor ?? skin.ink) : skin.faint,
                ghostColor: skin.faint.withOpacity(0.12),
              ),
              const SizedBox(width: 5),
              Text(
                unit,
                style: TextStyle(
                  color: skin.dim,
                  fontSize: fontSize * 0.30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
