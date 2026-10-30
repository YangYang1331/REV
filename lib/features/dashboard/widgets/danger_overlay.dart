import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';

/// 全屏红屏危险告警：仅在水温达 danger 或转速逼近红区时闪烁。
/// 阈值取自车型档案，避免硬编码“狼来了”。
class DangerOverlay extends StatefulWidget {
  const DangerOverlay({
    super.key,
    required this.active,
    required this.reason,
    required this.skin,
  });
  final bool active;
  final String reason;
  final SkinDescriptor skin;

  @override
  State<DangerOverlay> createState() => _DangerOverlayState();
}

class _DangerOverlayState extends State<DangerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void didUpdateWidget(DangerOverlay old) {
    super.didUpdateWidget(old);
    if (widget.active) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final on = widget.active && _c.value > 0.45;
          return Opacity(
            opacity: widget.active ? 0.28 + _c.value * 0.32 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    (on ? widget.skin.bad : widget.skin.warn)
                        .withOpacity(0.55),
                  ],
                ),
                border: Border.all(
                  color: widget.skin.bad.withOpacity(on ? 0.9 : 0.3),
                  width: 6,
                ),
              ),
              child: Center(
                child: Opacity(
                  opacity: on ? 1 : 0.4,
                  child: Text(
                    widget.reason,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'DSEG7',
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      shadows: [
                        Shadow(color: widget.skin.bad, blurRadius: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
