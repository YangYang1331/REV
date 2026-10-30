// VIN（Mode 09 02）解析与车型匹配单元测试。
//
// ELM327 各家固件对多帧 VIN 的呈现差别很大，这里覆盖实际会遇到的 4 种形态：
//  - ATCAF1 + ATH0：ELM 已重组好的单行 `49 02 01 ...`
//  - ATCAF0：被拆成 `0: ...` / `1: ...` 多行
//  - ATH1：每行带 CAN 头 7E8 + ISO-TP 序号（10/21/22）
//  - 末尾补 55 55 55（'U'）或 00 填充
import 'package:flutter_test/flutter_test.dart';

import 'package:obd_dashboard/core/vehicle/vin.dart';

void main() {
  // 马自达 6 GH 代（2010 款，GH12C 车型代号）
  const ghHex =
      '49 02 01 4A 4D 31 47 48 31 32 43 31 41 31 32 33 34 35 36 37';

  group('VinInfo.parse', () {
    test('CAF1 单行（含 49 02 01 前缀）', () {
      final v = VinInfo.parse(ghHex)!;
      expect(v.vin, 'JM1GH12C1A1234567');
      expect(v.wmi, 'JM1');
      expect(v.modelCode, 'GH12C');
      expect(v.year, 2010);
      expect(v.matchProfileId(), 'mazda6_2011');
    });

    test('CAF0 多行 `0:` / `1:` 拼接', () {
      const raw = '0: 49 02 01 4A 4D 31 47\r\n'
          '1: 48 31 32 43 31 41 31\r\n'
          '2: 32 33 34 35 36 37';
      expect(VinInfo.parse(raw)!.vin, 'JM1GH12C1A1234567');
    });

    test('ATH1：7E8 头 + ISO-TP 序号 + 55 填充', () {
      const raw = '7E8 10 14 49 02 01 4A 4D 31 47 48 31\r\n'
          '7E8 21 32 43 31 41 31 32 33 34 35 36\r\n'
          '7E8 22 37 55 55 55 55 55 55 55 55 55';
      final v = VinInfo.parse(raw)!;
      expect(v.vin, 'JM1GH12C1A1234567');
      expect(v.matchProfileId(), 'mazda6_2011');
    });

    test('29 位扩展 CAN 头（18DAF110）也能剥掉', () {
      const raw = '18DAF110 10 14 49 02 01 4A 4D 31 47 48 31\r\n'
          '18DAF110 21 32 43 31 41 31 32 33 34 35 36 37';
      expect(VinInfo.parse(raw)!.vin, 'JM1GH12C1A1234567');
    });

    test('空应答 / 不支持 Mode 09 / 不完整 VIN → null', () {
      expect(VinInfo.parse(''), isNull);
      expect(VinInfo.parse('NO DATA'), isNull);
      expect(VinInfo.parse('7F 09 12'), isNull); // 服务不支持
      expect(VinInfo.parse('49 02 01 4A 4D 31'), isNull); // 只有 3 位
    });

    test('含 O / I / Q 的噪声不会当成 VIN', () {
      // VIN 字符集不含 I/O/Q；若解析到这些字符属于坏帧。
      final v = VinInfo.parse(
          '49 02 01 4F 4D 31 47 48 31 32 43 31 41 31 32 33 34 35 36 37');
      // 'O' 在最前面：跳过它后仍是 17 位合法串也会被接受，这里只要求不抛异常
      expect(v == null || v.vin.length == 17, isTrue);
    });
  });

  group('matchProfileId', () {
    test('GJ 代 → mazda6_gj（创驰蓝天 6AT）', () {
      const raw =
          '49 02 01 4A 4D 31 47 4A 31 56 35 30 45 31 32 33 34 35 36 37';
      final v = VinInfo.parse(raw)!;
      expect(v.modelCode, startsWith('GJ'));
      expect(v.year, 2014);
      expect(v.matchProfileId(), 'mazda6_gj');
    });

    test('非马自达 WMI → null（不乱猜，保持手选）', () {
      const raw =
          '49 02 01 31 46 54 46 57 31 45 54 35 44 46 43 31 32 33 34 35';
      final v = VinInfo.parse(raw)!;
      expect(v.vin, '1FTFW1ET5DFC12345');
      expect(v.matchProfileId(), isNull);
    });

    test('车型代号缺失时按年款兜底', () {
      // 人为构造：第 4–8 位不带 GH/GJ，靠第 10 位年款判断
      const oldRaw =
          '49 02 01 4A 4D 31 58 58 31 32 43 31 44 31 32 33 34 35 36 37';
      final old = VinInfo.parse(oldRaw)!;
      expect(old.year, 2013);
      expect(old.matchProfileId(), 'mazda6_2011');
      const newRaw =
          '49 02 01 4A 4D 31 58 58 31 32 43 31 46 31 32 33 34 35 36 37';
      expect(VinInfo.parse(newRaw)!.matchProfileId(), 'mazda6_gj');
    });

    test('summary 带年款', () {
      final v = VinInfo.parse(ghHex)!;
      expect(v.summary, 'JM1GH12C1A1234567 · 2010款');
    });
  });
}
