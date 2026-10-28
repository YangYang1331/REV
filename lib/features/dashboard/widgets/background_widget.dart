import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';

/// 皮肤背景：横屏按宽高比桶（normal/18x9/wide）选图并 cover；
/// 竖屏时 NERV 背景含内置标题/立绘，裁切会露馅，改用纯底 + 光晕；
/// 上方叠加一层暗色压暗，保证前景数码管对比度。
class SkinBackground extends StatelessWidget {
  const SkinBackground({
    super.key,
    required this.skin,
    required this.child,
    this.dim = 0.35,
  });
  final SkinDescriptor skin;
  final Widget child;
  final double dim;

  /// 竖屏直接用背景图会把内置文字/Logo 裁坏的皮肤。
  static const _portraitImageBroken = {'nerv'};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final aspect = constraints.maxWidth / constraints.maxHeight;
      final isPortrait = aspect < 1.2;
      final useImage = !isPortrait || !_portraitImageBroken.contains(skin.id);
      final asset = useImage ? skin.backgroundAssetFor(aspect) : null;

      return DecoratedBox(
        decoration: BoxDecoration(color: skin.background),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              Image.asset(asset, fit: BoxFit.cover, alignment: Alignment.topCenter,
                  cacheWidth: 1366),
            if (isPortrait && !useImage)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.6),
                    radius: 1.1,
                    colors: [
                      skin.accent.withOpacity(0.10),
                      skin.background.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            // 渐变压暗：底部更暗，保证读数对比
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(dim * 0.4),
                    Colors.black.withOpacity(dim),
                  ],
                ),
              ),
            ),
            child,
          ],
        ),
      );
    });
  }
}
