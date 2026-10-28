// v2.13.0 新增纯逻辑单测：
//  1) ATSP0 自动探测后 ATDPN 应答 → ObdProtocol 枚举；
//  2) PID 坏帧 / 越界 / 跳变过滤；
//  3) Mode 03 DTC 解析；
//  4) Mode 04 清码命令构造；
//  5) 批量响应对齐（守护旧逻辑不回归）。
import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/obd/obd_pid.dart';
import 'package:obd_dashboard/core/obd/obd_protocol.dart';
import 'package:obd_dashboard/core/obd/pid_sanity.dart';

void main() {
  group('ATDPN 协议探测解析（ATSP0 后回读）', () {
    test('马6 协议 6 → can11bit500', () {
      final info = parseActiveProtocol('6');
      expect(info.protocol, ObdProtocol.can11bit500);
      expect(info.rawCode, '6');
      expect(info.autoSelected, isFalse);
      expect(info.protocol.isMazda6Target, isTrue);
    });

    test('ATSP0 自动模式下 A6 → can11bit500 + autoSelected', () {
      final info = parseActiveProtocol('A6');
      expect(info.protocol, ObdProtocol.can11bit500);
      expect(info.autoSelected, isTrue);
    });

    test('其他协议号映射正确', () {
      expect(parseActiveProtocol('1').protocol, ObdProtocol.saeJ1850Pwm);
      expect(parseActiveProtocol('2').protocol, ObdProtocol.saeJ1850Vpw);
      expect(parseActiveProtocol('3').protocol, ObdProtocol.iso9141);
      expect(parseActiveProtocol('4').protocol, ObdProtocol.kwp2000_5baud);
      expect(parseActiveProtocol('5').protocol, ObdProtocol.kwp2000Fast);
      expect(parseActiveProtocol('7').protocol, ObdProtocol.can29bit500);
      expect(parseActiveProtocol('8').protocol, ObdProtocol.can11bit250);
      expect(parseActiveProtocol('9').protocol, ObdProtocol.can29bit250);
    });

    test('噪声/提示符/空应答 → unknown', () {
      expect(parseActiveProtocol('').protocol, ObdProtocol.unknown);
      expect(parseActiveProtocol('?').protocol, ObdProtocol.unknown);
      expect(parseActiveProtocol('NO DATA').protocol, ObdProtocol.unknown);
      // 带提示符残留
      expect(parseActiveProtocol('6>').protocol, ObdProtocol.can11bit500);
      // 带空格
      expect(parseActiveProtocol(' A6 ').protocol, ObdProtocol.can11bit500);
    });

    test('CAN 类协议 isCan=true，K-line 类 false', () {
      expect(ObdProtocol.can11bit500.isCan, isTrue);
      expect(ObdProtocol.can29bit500.isCan, isTrue);
      expect(ObdProtocol.iso9141.isCan, isFalse);
      expect(ObdProtocol.kwp2000Fast.isCan, isFalse);
    });
  });

  group('PID 坏帧 / 越界过滤', () {
    test('rpm 跳到 3 万（物理不可能）被丢弃', () {
      expect(PidSanity.isPhysicallyPlausible(Pid.rpm, 30000), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.rpm, -100), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.rpm, 2000), isTrue);
    });

    test('速度负值被丢弃', () {
      expect(PidSanity.isPhysicallyPlausible(Pid.speed, -5), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.speed, 120), isTrue);
      expect(PidSanity.isPhysicallyPlausible(Pid.speed, 300), isFalse);
    });

    test('水温低于 -40（ECU 哨兵以下）被丢弃', () {
      expect(PidSanity.isPhysicallyPlausible(Pid.coolant, -50), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.coolant, -40), isTrue);
      expect(PidSanity.isPhysicallyPlausible(Pid.coolant, 90), isTrue);
      expect(PidSanity.isPhysicallyPlausible(Pid.coolant, 200), isFalse);
    });

    test('油门/负荷百分比越界被丢弃', () {
      expect(PidSanity.isPhysicallyPlausible(Pid.throttle, 120), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.throttle, -10), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.engineLoad, 50), isTrue);
    });

    test('电压 5V / 20V 判坏帧，12V 合法', () {
      expect(PidSanity.isPhysicallyPlausible(Pid.voltage, 5), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.voltage, 20), isFalse);
      expect(PidSanity.isPhysicallyPlausible(Pid.voltage, 12.4), isTrue);
    });

    test('跳变过滤：rpm 0.1s 内从 800 跳到 5000 判坏帧', () {
      expect(PidSanity.isDeltaPlausible(Pid.rpm, 800, 5000), isFalse);
      expect(PidSanity.isDeltaPlausible(Pid.rpm, 800, 1500), isTrue);
    });

    test('跳变过滤：速度 0.1s 内从 0 跳到 100 km/h 判坏帧', () {
      expect(PidSanity.isDeltaPlausible(Pid.speed, 0, 100), isFalse);
      expect(PidSanity.isDeltaPlausible(Pid.speed, 60, 70), isTrue);
    });

    test('跳变过滤：水温瞬间跳 30℃ 判坏帧', () {
      expect(PidSanity.isDeltaPlausible(Pid.coolant, 80, 110), isFalse);
      expect(PidSanity.isDeltaPlausible(Pid.coolant, 80, 85), isTrue);
    });

    test('首帧无基线（prev=null）只查物理范围', () {
      expect(PidSanity.accept(Pid.rpm, null, 2000), isTrue);
      expect(PidSanity.accept(Pid.rpm, null, 99999), isFalse);
    });
  });

  group('Mode 03 DTC 解析', () {
    test('单码 P0171 解析正确（带 count 头）', () {
      // 43 01 0171 → count=1, b0=0x01 b1=0x71
      // family = 00 → P；high bit (b0>>4)&3 = 0；d1=1；d2=7；d3=1 → P0171
      final codes = DtcCodec.parseMode03('43010171');
      expect(codes, ['P0171']);
    });

    test('多码拼接解析正确', () {
      // count=2, P0301 + U0100
      // P0301: family=00, digit1=0, digit2=3 → b0=0x03; b1=0x01
      // U0100: family=11, digit1=0, digit2=1 → b0=(3<<6)|1=0xC1; b1=0x00
      final codes = DtcCodec.parseMode03('43020301C100');
      expect(codes, contains('P0301'));
      expect(codes, contains('U0100'));
    });

    test('count=0 表示无故障码', () {
      expect(DtcCodec.parseMode03('4300'), isEmpty);
    });

    test('噪声/非 43 开头返回空', () {
      expect(DtcCodec.parseMode03('NO DATA'), isEmpty);
      expect(DtcCodec.parseMode03(''), isEmpty);
      expect(DtcCodec.parseMode03('410C1F88'), isEmpty);
    });

    test('带空格与提示符的行也能解析', () {
      expect(DtcCodec.parseMode03('43 01 0171>'), ['P0171']);
    });
  });

  group('Mode 04 清码命令构造', () {
    test('命令字是 "04"', () {
      expect(DtcCodec.clearCommand, '04');
    });

    test('读码命令字是 "03"', () {
      expect(DtcCodec.readCommand, '03');
    });

    test('正响应标记是 "43"', () {
      expect(DtcCodec.positiveMarker, '43');
    });
  });

  group('批量响应对齐（旧逻辑守护）', () {
    test('紧凑批量响应按顺序切到各 PID', () {
      const raw = '410C1F880D3C055011200432';
      final m = PidParser.parseMultiSequential(raw);
      expect(m[Pid.rpm], closeTo(2018, 0.01));
      expect(m[Pid.speed], closeTo(60, 0.01));
      expect(m[Pid.coolant], closeTo(40, 0.01));
    });

    test('未知 PID 对齐失效即停，不错位消费后续字节', () {
      // 41 0C A8 F0 | 0D 3C —— 故意塞个未知 code "ZZ" 之前的非法段
      final m = PidParser.parseMultiSequential('410CA8F00D3C');
      expect(m[Pid.rpm], isNotNull);
      expect(m[Pid.speed], isNotNull);
    });
  });
}
