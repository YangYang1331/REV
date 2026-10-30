import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/obd/deep_diagnostic.dart';

void main() {
  group('深诊断：待定码 / 永久码', () {
    test('Mode 07 解析（47）', () {
      // 47 02 01 23 04 56 → P0123, P0456
      final codes = DeepDiagnosticCodec.parseCodes('47 02 01 23 04 56', '47');
      expect(codes, ['P0123', 'P0456']);
    });

    test('Mode 0A 解析（4A），无码返回空', () {
      expect(DeepDiagnosticCodec.parseCodes('4A 00', '4A'), isEmpty);
      expect(DeepDiagnosticCodec.parseCodes('NO DATA', '4A'), isEmpty);
    });

    test('带 CAN 头/空格也能解析', () {
      final codes =
          DeepDiagnosticCodec.parseCodes('7E8 06 47 01 03 00 00 00', '47');
      expect(codes, ['P0300']);
    });
  });

  group('深诊断：排放就绪', () {
    test('MIL 点亮 + 6 项未完成', () {
      // A=83(MIL,3 码) B=07(失火/燃油/综合 支持但未完成，汽油) C=65 D=04
      final r = DeepDiagnosticCodec.parseReadiness('41 01 83 07 65 04');
      expect(r, isNotNull);
      expect(r!.milOn, isTrue);
      expect(r.dtcCount, 3);
      final names = r.monitors.map((m) => m.name).toList();
      expect(names, contains('失火监测'));
      expect(names, contains('催化器'));
      expect(names, contains('蒸发系统 EVAP'));
      expect(names, contains('氧传感器'));
      expect(names, isNot(contains('二次空气')));
      // EVAP 在 D 的 bit2 已完成，其余未完成
      final evap = r.monitors.firstWhere((m) => m.name.contains('EVAP'));
      expect(evap.complete, isTrue);
      expect(r.ready, isFalse);
      expect(r.incomplete.length, 6); // 失火/燃油/综合 + 催化/氧传感/氧传感加热
    });

    test('柴油位序：失火等已完成，EGR 未完成', () {
      // B=7F(bit3=1 柴油，三项通用均完成) C=81(NMHC + EGR) D=01(NMHC 完成)
      final r = DeepDiagnosticCodec.parseReadiness('41 01 81 7F 81 01');
      expect(r, isNotNull);
      expect(r!.monitors.map((m) => m.name), [
        '失火监测',
        '燃油系统',
        '综合组件',
        'NMHC 催化器',
        'EGR / VVT',
      ]);
      expect(r.incomplete.map((m) => m.name), ['EGR / VVT']);
    });

    test('全部完成 → ready', () {
      final r = DeepDiagnosticCodec.parseReadiness('41 01 00 00 01 01');
      expect(r, isNotNull);
      expect(r!.milOn, isFalse);
      expect(r.ready, isTrue);
    });

    test('应答不完整返回 null', () {
      expect(DeepDiagnosticCodec.parseReadiness('41 01 00'), isNull);
      expect(DeepDiagnosticCodec.parseReadiness('NO DATA'), isNull);
    });
  });

  group('深诊断：冻结帧', () {
    test('触发码解析', () {
      expect(DeepDiagnosticCodec.parseFreezeDtc('42 02 00 01 23'), 'P0123');
      expect(DeepDiagnosticCodec.parseFreezeDtc('42 02 00 00 00'), isNull);
    });

    test('转速与车速解码', () {
      final rpm = DeepDiagnosticCodec.parseFreezePid('42 0C 00 1A F8', 0x0C);
      expect(rpm, isNotNull);
      expect(rpm!.value, closeTo(1726, 0.1));
      final speed = DeepDiagnosticCodec.parseFreezePid('42 0D 00 50', 0x0D);
      expect(speed!.value, 80);
    });

    test('温度与电压解码', () {
      final coolant =
          DeepDiagnosticCodec.parseFreezePid('42 05 00 5A', 0x05);
      expect(coolant!.value, 50);
      final volt = DeepDiagnosticCodec.parseFreezePid('42 42 00 30 39', 0x42);
      expect(volt!.value, closeTo(12.345, 0.01));
    });
  });
}
