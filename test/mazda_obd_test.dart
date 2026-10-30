// 马自达 6 适配测试：
//  1) Mode 22（UDS 0x22）支持位图解析 —— 扩展 PID 探测的解析内核；
//  2) 档位反推（K = rpm/speed）与迟滞 —— 声浪“闷音”逻辑依赖档位。
import 'package:flutter_test/flutter_test.dart';

import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/services/obd_service.dart';

void main() {
  group('Mode 22 支持位图解析', () {
    test('首字节最高位 = base+1', () {
      // 62 00 80 00 00 00 → 只支持 0x01
      expect(ObdService.parseMode22Mask(0x00, '620080000000'), {0x01});
    });

    test('全 1 掩码 → 该组 32 个 PID', () {
      final s = ObdService.parseMode22Mask(0x20, '62 20 FF FF FF FF');
      expect(s.length, 32);
      expect(s.first, 0x21);
      expect(s.last, 0x40);
    });

    test('首字节第 7 位表示 base+2', () {
      expect(ObdService.parseMode22Mask(0x00, '620040000000'), {0x02});
    });

    test('否定应答 / NO DATA / 缺字节 → 空集', () {
      expect(ObdService.parseMode22Mask(0x00, '7F 22 31'), isEmpty);
      expect(ObdService.parseMode22Mask(0x00, 'NO DATA'), isEmpty);
      expect(ObdService.parseMode22Mask(0x00, '62008000'), isEmpty);
      expect(ObdService.parseMode22Mask(0x00, ''), isEmpty);
    });

    test('带提示符与空格的原始行可解析（末字节最低位 = base+32）', () {
      expect(
        ObdService.parseMode22Mask(0x20, '62 20 00 00 00 01>'),
        {0x40},
      );
    });

    test('掩码不越过单字节 DID 上限', () {
      final s = ObdService.parseMode22Mask(0xE0, '62 E0 FF FF FF FF');
      expect(s.contains(0x100), isFalse);
      expect(s.contains(0xFF), isTrue);
    });
  });

  group('档位反推（马自达 6）', () {
    test('2011 款 5AT：各档位按齿比命中', () {
      final p = VehicleProfile.byId('mazda6_2011');
      final kt = p.gearKTable();
      for (var i = 0; i < kt.length; i++) {
        final speed = 30.0 + i * 15; // 30..90 km/h
        final rpm = kt[i] * speed;
        expect(p.estimateGear(rpm, speed), i + 1,
            reason: '${i + 1} 挡 K=${kt[i]}');
      }
    });

    test('2011 款 5AT：5 挡 120km/h ≈ 2800–2900rpm（实车锚点）', () {
      final p = VehicleProfile.byId('mazda6_2011');
      final rpm = p.rpmForSpeed(5, 120);
      expect(rpm, inInclusiveRange(2700, 2950),
          reason: '5 挡 120km/h 实测约 2800rpm，齿比表 K5=${p.gearKTable()[4]}');
      expect(p.estimateGear(rpm, 120), 5);
      // 4 挡 100km/h ≈ 3250rpm
      expect(p.estimateGear(p.rpmForSpeed(4, 100), 100), 4);
    });

    test('2014+ 创驰蓝天 6AT：6 挡 100km/h ≈ 2000rpm', () {
      final p = VehicleProfile.byId('mazda6_gj');
      final kt = p.gearKTable();
      final rpm = kt[5] * 100;
      expect(p.estimateGear(rpm, 100), 6);
      expect(rpm, inInclusiveRange(1800, 2300));
    });

    test('迟滞：上一档仍成立时不跳挡', () {
      final p = VehicleProfile.byId('mazda6_gj');
      final kt = p.gearKTable();
      final speed = 60.0;
      final k3 = kt[2] * speed;
      // 3 挡区间中点：无论是否给 prev 都是 3
      expect(p.estimateGear(k3, speed), 3);
      expect(p.estimateGear(k3, speed, prevGear: 3), 3);
      // 略高于 3 挡理论 K（变矩器滑移）：无 prev 时可能判 4，
      // 带 prev=3 时保持 3
      final kSlip = k3 * 1.18;
      expect(p.estimateGear(kSlip, speed, prevGear: 3), 3);
    });

    test('真实换挡后不被迟滞锁死', () {
      final p = VehicleProfile.byId('mazda6_gj');
      final kt = p.gearKTable();
      final speed = 60.0;
      // 已升到 4 挡的转速：prev=3 也必须改判 4
      expect(p.estimateGear(kt[3] * speed, speed, prevGear: 3), 4);
    });

    test('静止 / 熄火 → 0（空挡）', () {
      final p = VehicleProfile.byId('mazda6_gj');
      expect(p.estimateGear(0, 0), 0);
      expect(p.estimateGear(700, 0), 0);
      expect(p.estimateGear(200, 40), 0); // 转速低于怠速*0.7
    });

    test('车型列表包含两款马自达 6 且 id 唯一', () {
      final ids = VehicleProfile.presets.map((p) => p.id).toList();
      expect(ids.contains('mazda6_2011'), isTrue);
      expect(ids.contains('mazda6_gj'), isTrue);
      expect(ids.toSet().length, ids.length);
    });
  });
}
