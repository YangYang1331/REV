import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/track/track_line_detector.dart';

void main() {
  group('TrackLineDetector', () {
    test('未学习起点返回 null', () {
      final d = TrackLineDetector();
      expect(d.feed(31.0, 121.0, 50, 0), isNull);
    });

    test('驶离外圈再冲线计一圈，重复进入不连计', () {
      final d = TrackLineDetector(crossRadiusM: 25, armRadiusM: 120);
      d.learnOrigin(31.0, 121.0);

      // t=0 在起点：未武装，不计圈。
      expect(d.feed(31.0, 121.0, 50, 0), isNull);

      // 驶离 ~222m > armRadius，武装。
      expect(d.feed(31.0020, 121.0, 60, 1000), isNull);

      // 60s 后回到起点附近 ~11m（<cross），在动 → 冲线。
      final res = d.feed(31.0001, 121.0, 50, 60000);
      expect(res, isNotNull);
      expect(res!.lap, 1);
      expect(res.lapSeconds, closeTo(59, 1));

      // 冲线后仍停在起点：未武装，不重复计圈。
      expect(d.feed(31.0001, 121.0, 50, 61000), isNull);

      // 再驶离一圈冲线，lap=2。
      d.feed(31.0020, 121.0, 60, 70000);
      final res2 = d.feed(31.0001, 121.0, 50, 120000);
      expect(res2!.lap, 2);
    });

    test('低速（挪车）不判定冲线', () {
      final d = TrackLineDetector(crossRadiusM: 25, armRadiusM: 120, minSpeedKmh: 5);
      d.learnOrigin(31.0, 121.0);
      d.feed(31.0020, 121.0, 60, 1000);
      // 回到起点但速度 2 < minSpeed → 不计。
      expect(d.feed(31.0001, 121.0, 2, 60000), isNull);
    });

    test('haversine 距离量级正确', () {
      // 纬度差 0.001° ≈ 111 m。
      final m = TrackLineDetector.haversineM(31.0, 121.0, 31.001, 121.0);
      expect(m, closeTo(111, 2));
    });
  });
}
