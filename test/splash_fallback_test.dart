import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/features/splash/splash_screen.dart';

/// 开屏导航【纯逻辑决策】单测：不初始化任何动画时钟/原生播放器，只验证
///  1. 开屏动画开关开/关：关 → 立即进主页（不播动画）；
///  2. 开关开：动画正常播完即进主页；
///  3. 超时回退：动画卡住（永不完成）时，9s 绝对硬上限兜底强制进主页，绝不白屏。
void main() {
  group('SplashNavPolicy', () {
    test('时间轴常量：计划 4.0s < 硬上限 9.0s', () {
      expect(SplashNavPolicy.plannedDuration, const Duration(milliseconds: 4000));
      expect(SplashNavPolicy.absoluteMaxHold, const Duration(milliseconds: 9000));
      expect(
        SplashNavPolicy.plannedDuration < SplashNavPolicy.absoluteMaxHold,
        isTrue,
      );
    });

    test('开关关闭 → 不播动画，立即进主页', () {
      final p = SplashNavPolicy(animationEnabled: false);
      expect(p.shouldPlayAnimation, isFalse);
      // 无论动画是否"完成"、流逝多久，都直接进主页。
      expect(p.shouldGoHome(elapsed: Duration.zero, animationCompleted: false), isTrue);
      expect(p.shouldGoHome(elapsed: const Duration(seconds: 1), animationCompleted: false), isTrue);
    });

    test('开关开启 + 动画正常完成 → 进主页', () {
      final p = SplashNavPolicy(animationEnabled: true);
      expect(p.shouldPlayAnimation, isTrue);
      expect(
        p.shouldGoHome(elapsed: SplashNavPolicy.plannedDuration, animationCompleted: true),
        isTrue,
      );
    });

    test('开关开启 + 动画未完成 + 未到硬上限 → 停留（继续播）', () {
      final p = SplashNavPolicy(animationEnabled: true);
      expect(
        p.shouldGoHome(
          elapsed: const Duration(seconds: 2),
          animationCompleted: false,
        ),
        isFalse,
      );
      expect(
        p.shouldGoHome(
          elapsed: SplashNavPolicy.plannedDuration, // 计划播完但回调"尚未标记完成"
          animationCompleted: false,
        ),
        isFalse,
      );
    });

    test('开关开启 + 动画卡住 + 到达 9s 硬上限 → 强制进主页（不白屏）', () {
      final p = SplashNavPolicy(animationEnabled: true);
      // 8.9s：还差一点，仍停留。
      expect(
        p.shouldGoHome(
          elapsed: const Duration(milliseconds: 8900),
          animationCompleted: false,
        ),
        isFalse,
      );
      // 9.0s：硬上限兜底，强制进主页。
      expect(
        p.shouldGoHome(
          elapsed: SplashNavPolicy.absoluteMaxHold,
          animationCompleted: false,
        ),
        isTrue,
      );
      expect(
        p.shouldGoHome(
          elapsed: const Duration(seconds: 15),
          animationCompleted: false,
        ),
        isTrue,
      );
    });
  });
}
