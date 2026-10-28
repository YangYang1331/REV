import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/perf/dyno_estimator.dart';

void main() {
  group('DynoEstimator', () {
    const inp = DynoInputs(massKg: 1500, drivetrainEfficiency: 0.85);

    test('车速为 0 时功率为 0', () {
      final e = DynoEstimator.estimate(inp, 5, 0, 3000);
      expect(e.crankHp, closeTo(0, 0.01));
    });

    test('正加速段输出正马力，曲轴 > 轮上', () {
      final e = DynoEstimator.estimate(inp, 5, 30, 4000);
      expect(e.wheelHp, greaterThan(0));
      expect(e.crankHp, greaterThan(e.wheelHp));
      // 1500*5=7500N，30m/s → ~286 轮上 hp，曲轴 ~337 hp。
      expect(e.crankHp, inExclusiveRange(250, 450));
      // 不确定带对称。
      expect(e.crankHpHigh - e.crankHp, closeTo(e.crankHp - e.crankHpLow, 1));
    });

    test('负加速（刹车）不输出负马力', () {
      final e = DynoEstimator.estimate(inp, -8, 30, 4000);
      expect(e.crankHp, greaterThanOrEqualTo(0));
    });

    test('扭矩在给定转速下为正', () {
      final e = DynoEstimator.estimate(inp, 5, 30, 4000);
      expect(e.torqueNm, greaterThan(0));
    });
  });
}
