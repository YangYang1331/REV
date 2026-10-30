import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/diagnostic/symptom_index.dart';

void main() {
  group('症状自查离线规则库', () {
    test('没有任何输入时返回空', () {
      expect(SymptomIndex.match(), isEmpty);
    });

    test('勾选怠速抖动：首推 P0300，且带严重度建议', () {
      final r = SymptomIndex.match(symptomIds: {'shake_idle'});
      expect(r, isNotEmpty);
      expect(r.first.code, 'P0300');
      expect(r.first.score, 4);
      expect(r.first.reasons, contains('怠速抖动 / 等红灯抖'));
      expect(r.first.advice.severity, 2);
      expect(r.first.advice.canDrive, isNotEmpty);
      expect(r.first.advice.cost, isNotEmpty);
    });

    test('多个症状叠加会累加权重，P0171 排前', () {
      final r = SymptomIndex.match(
          symptomIds: {'no_power', 'high_fuel', 'o2'});
      expect(r, isNotEmpty);
      expect(r.first.code, 'P0171');
      expect(r.first.score, greaterThanOrEqualTo(9));
    });

    test('自由文本命中症状标签', () {
      final r = SymptomIndex.match(freeText: '等红灯方向盘抖');
      expect(r, isNotEmpty);
      expect(r.map((e) => e.code), contains('P0300'));
    });

    test('自由文本命中故障码释义关键词', () {
      final r = SymptomIndex.match(freeText: '汽油味 油箱盖');
      expect(r, isNotEmpty);
      expect(r.map((e) => e.code), contains('P0455'));
    });

    test('limit 生效', () {
      final r = SymptomIndex.match(
          symptomIds: {'misfire', 'shake_idle', 'stall'}, limit: 3);
      expect(r.length, lessThanOrEqualTo(3));
    });

    test('相同分数时严重度高的排前面', () {
      final r = SymptomIndex.match(symptomIds: {'hard_start'});
      for (var i = 1; i < r.length; i++) {
        if (r[i].score == r[i - 1].score) {
          expect(r[i - 1].advice.severity,
              greaterThanOrEqualTo(r[i].advice.severity));
        }
      }
    });
  });
}
