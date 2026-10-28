import 'package:flutter/material.dart';

/// 皮肤布局类型（决定用哪个仪表盘渲染器）。
enum SkinLayout {
  metro,
  nerv,
  touge,
  nervr,
  apex,
  cluster,
  cyanHex,
  supercar,
  amberGt,
  amberNerv,
}

/// 一套皮肤的设计令牌（色 / 字 / 背景）。
/// 单一主色相、带色相倾向的中性色，避免“AI 模板脸”。
class SkinDescriptor {
  const SkinDescriptor({
    required this.id,
    required this.label,
    required this.layout,
    required this.background,
    required this.panel,
    required this.panelStroke,
    required this.ink,
    required this.dim,
    required this.faint,
    required this.accent,
    required this.accent2,
    required this.warn,
    required this.bad,
    required this.ok,
    this.bgImageBase,
    this.glowColor,
  });

  final String id;
  final String label;
  final SkinLayout layout;

  final Color background;     // 基底
  final Color panel;          // 卡片/玻璃底
  final Color panelStroke;    // 玻璃边缘（描边比填充更塑造玻璃）
  final Color ink;            // 主文字
  final Color dim;            // 次要文字
  final Color faint;          // 弱文字/刻度
  final Color accent;         // 主强调（唯一主色相）
  final Color accent2;        // 次强调（少量冷色）
  final Color warn;
  final Color bad;
  final Color ok;

  /// 背景图文件名前缀（不含比例后缀）；null 表示纯渐变底。
  final String? bgImageBase;
  /// 背景光斑色（玻璃质感用）。
  final Color? glowColor;

  bool get hasImage => bgImageBase != null;
  bool get isDark => true;

  /// 按宽高比选背景图：normal / 18x9 / wide。
  String? backgroundAssetFor(double aspect) {
    if (bgImageBase == null) return null;
    if (aspect >= 2.12) return 'assets/images/${bgImageBase}_wide.jpg';
    if (aspect >= 1.95) return 'assets/images/${bgImageBase}_18x9.jpg';
    return 'assets/images/$bgImageBase.jpg';
  }
}
