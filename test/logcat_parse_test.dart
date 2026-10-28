import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/services/logcat_channel.dart';

void main() {
  group('LogcatChannel.parseLine', () {
    test('匹配 RPM=3200 / speed: 45 kmh / gear=3', () {
      final p = LogcatChannel.parseLine('I/CAN: rpm=3200 speed: 45.5 kmh gear=3');
      expect(p, isNotNull);
      expect(p!.rpm, 3200);
      expect(p.speedKmh, closeTo(45.5, 0.01));
      expect(p.gear, 3);
    });

    test('无车辆数据行返回 null', () {
      expect(LogcatChannel.parseLine('D/Rev: app started'), isNull);
    });

    test('仅 rpm 也返回', () {
      final p = LogcatChannel.parseLine('E/vendor: RPM: 800');
      expect(p!.rpm, 800);
    });
  });
}
