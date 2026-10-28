import 'package:flutter/material.dart';

/// 演示 / 离线模式封条：左上角亮橙色斜角丝带，醒目标注「DEMO 演示」。
///
/// 仅在演示 / 离线模式由外层控制是否插入（如 `if (t.isOffline) DemoSeal()`），
/// 组件本身无状态、不读 Provider、不拦截触摸（IgnorePointer），不遮挡核心数据。
/// 带轻微呼吸 + 斜向扫光动画，让用户一眼认出这是演示数据而非真实行车。
class DemoSeal extends StatelessWidget {
  const DemoSeal({
    super.key,
    this.text = 'DEMO 演示',
    this.color = const Color(0xFFFFB02E),
    this.align = Alignment.topLeft,
  });

  /// 封条文字。
  final String text;

  /// 警示色（默认橙黄，与皮肤 warn 一致）。
  final Color color;

  /// 出现位置（默认左上角，可改右上角）。
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: IgnorePointer(
        child: _Breath(
          child: Container(
            margin: const EdgeInsets.only(left: 14, top: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.92),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                bottomRight: Radius.circular(6),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.55),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.black.withOpacity(0.85)),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF1A1206),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 轻量呼吸动画（0.9~1.0 透明度周期 1.6s）；私有实现，对外保持 DemoSeal 无状态。
class _Breath extends StatefulWidget {
  const _Breath({required this.child});
  final Widget child;

  @override
  State<_Breath> createState() => _BreathState();
}

class _BreathState extends State<_Breath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Opacity(
          opacity: 0.88 + t * 0.12,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
