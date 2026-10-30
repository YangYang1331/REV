import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/fuel/fuel_log.dart';

FuelRec full(int ts, double odo, double liters, {double price = 8}) =>
    FuelRec(ts: ts, odo: odo, liters: liters, unitPrice: price);

FuelRec part(int ts, double odo, double liters, {double price = 8}) =>
    FuelRec(
        ts: ts, odo: odo, liters: liters, unitPrice: price, full: false);

void main() {
  group('加油记录与长期油耗', () {
    test('空记录', () {
      final s = FuelStats.of([]);
      expect(s.segments, isEmpty);
      expect(s.avgL100, isNull);
      expect(s.costPerKm, isNull);
      expect(s.fills, 0);
    });

    test('满箱 → 满箱：50L / 500km = 10 L/100km', () {
      final s = FuelStats.of([
        full(1, 1000, 40),
        full(2, 1500, 50),
      ]);
      expect(s.segments.length, 1);
      expect(s.avgL100, closeTo(10, 1e-9));
      expect(s.lastL100, closeTo(10, 1e-9));
      expect(s.costPerKm, closeTo(0.8, 1e-9));
      expect(s.totalLiters, 90);
      expect(s.totalCost, closeTo(720, 1e-9));
      expect(s.fills, 2);
    });

    test('中途加半箱：油量计入区间，里程从上次加满算', () {
      final s = FuelStats.of([
        full(1, 1000, 40),
        part(2, 1200, 20),
        full(3, 1500, 30),
      ]);
      expect(s.segments.length, 1);
      expect(s.segments.first.liters, 50);
      expect(s.segments.first.km, 500);
      expect(s.avgL100, closeTo(10, 1e-9));
    });

    test('乱序输入也能按里程正确分段', () {
      final s = FuelStats.of([
        full(3, 1500, 30),
        full(1, 1000, 40),
        full(2, 1200, 10),
      ]);
      expect(s.segments.length, 2);
      expect(s.avgL100, closeTo(40 / 500 * 100, 1e-9));
    });

    test('最近 3 段 vs 更早的趋势', () {
      final recs = <FuelRec>[
        full(1, 0, 50),
        full(2, 500, 50), // 10
        full(3, 1000, 50), // 10
        full(4, 1500, 50), // 10
        full(5, 2000, 60), // 12
        full(6, 2500, 60), // 12
        full(7, 3000, 60), // 12
      ];
      final s = FuelStats.of(recs);
      expect(s.segments.length, 6);
      expect(s.recentL100(3), closeTo(12, 1e-9));
      expect(s.trendL100, closeTo(2, 1e-9));
    });

    test('少于 4 段时趋势为 null', () {
      final s = FuelStats.of([
        full(1, 0, 50),
        full(2, 500, 50),
        full(3, 1000, 50),
      ]);
      expect(s.segments.length, 2);
      expect(s.trendL100, isNull);
    });

    test('单段里程太小不参与统计', () {
      final s = FuelStats.of([
        full(1, 1000, 40),
        full(2, 1000.5, 20),
      ]);
      expect(s.segments, isEmpty);
      expect(s.avgL100, isNull);
      expect(s.totalLiters, 60);
    });
  });

  group('到期提醒', () {
    test('30 天内提示 soon，过期提示 overdue', () {
      final soon = DueInfo('保险', DateTime.now().add(const Duration(days: 10)));
      expect(soon.soon, isTrue);
      expect(soon.overdue, isFalse);
      final over = DueInfo('年检', DateTime.now().subtract(const Duration(days: 5)));
      expect(over.overdue, isTrue);
      expect(over.soon, isFalse);
    });
  });
}
