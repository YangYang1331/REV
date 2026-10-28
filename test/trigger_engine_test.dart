import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/rules/trigger_engine.dart';

void main() {
  group('TriggerEngine', () {
    test('水温超过阈值触发红屏，滞回回落才解除', () {
      final eng = TriggerEngine(rules: const [
        TriggerRule(
          id: 'hot',
          metric: TriggerMetric.coolant,
          op: TriggerOp.above,
          threshold: 105,
          hysteresis: 5,
          action: TriggerAction(redScreen: true),
        ),
      ]);

      // 100：不触发。
      expect(eng.update(const TriggerSample(coolant: 100)).hasFired, isFalse);
      // 106：刚越过，触发。
      final fired = eng.update(const TriggerSample(coolant: 106));
      expect(fired.hasFired, isTrue);
      expect(fired.justFired.redScreen, isTrue);
      expect(fired.activeIds.contains('hot'), isTrue);
      // 104：仍高于 100（105-5），不解除也不重复触发。
      final still = eng.update(const TriggerSample(coolant: 104));
      expect(still.hasFired, isFalse); // 边沿事件只发一次
      expect(still.activeIds.contains('hot'), isTrue);
      // 99：低于 100，解除。
      final rel = eng.update(const TriggerSample(coolant: 99));
      expect(rel.activeIds.contains('hot'), isFalse);
    });

    test('转速低于阈值触发换挡灯（above/below）', () {
      final eng = TriggerEngine(rules: const [
        TriggerRule(
          id: 'revlim',
          metric: TriggerMetric.rpm,
          op: TriggerOp.above,
          threshold: 6800,
          hysteresis: 200,
          action: TriggerAction(shiftLamp: true),
        ),
      ]);
      expect(eng.update(const TriggerSample(rpm: 6900)).justFired.shiftLamp, isTrue);
      expect(eng.update(const TriggerSample(rpm: 6700)).justFired.shiftLamp, isFalse);
    });

    test('量缺失时跳过规则', () {
      final eng = TriggerEngine(rules: const [
        TriggerRule(
          id: 'v',
          metric: TriggerMetric.voltage,
          op: TriggerOp.below,
          threshold: 11.5,
          action: TriggerAction(announce: true),
        ),
      ]);
      expect(eng.update(const TriggerSample()).hasFired, isFalse);
      expect(eng.update(const TriggerSample(voltage: 11.0)).justFired.announce,
          isTrue);
    });
  });
}
