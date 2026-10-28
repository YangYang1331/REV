// 故障码解码器单元测试：精确字典命中 + SAE J2012 码位规则兜底 + 非法码兜底。
// 守护"任意合法码都有解释、绝不留白"，且精确码与标准推断码 isGeneric 标记正确；
// 精确码优先于规则推断。
import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';

void main() {
  group('DTC 精确字典', () {
    test('常见码精确命中', () {
      final thin = DtcDatabase.explain('P0171');
      expect(thin.title, '第1排混合气过稀');
      expect(thin.isGeneric, isFalse, reason: '精确字典码不应标 isGeneric');
      expect(thin.causes, isNotEmpty);
      expect(thin.suggestion, isNotEmpty);

      expect(DtcDatabase.explain('P0420').title, '第1排三元催化器效率过低');
      expect(DtcDatabase.explain('P0301').title, '第1缸失火');
      expect(DtcDatabase.explain('P0301').isGeneric, isFalse);
    });

    test('各家族关键码精确命中中文描述与原因', () {
      // 用 (码, 期望标题包含的关键片段) 批量守护。
      const cases = <String, String>{
        'P0300': '随机',
        'P0301': '第1缸失火',
        'P0130': '前氧',
        'P0135': '前氧',
        'P0420': '三元催化',
        'P0442': '小泄漏',
        'P0400': 'EGR',
        'P0102': '空气流量',
        'P0123': '节气门位置传感器A',
        'P0500': '车速传感器',
        'P0562': '系统电压过低',
        'P0700': '变速箱控制',
        'P0740': '变矩器',
        'U0100': 'ECM/PCM',
      };
      cases.forEach((code, expectFragment) {
        final d = DtcDatabase.explain(code);
        expect(d.title, contains(expectFragment), reason: '$code 应命中精确中文描述');
        expect(d.isGeneric, isFalse, reason: '$code 必须为精确字典码');
        expect(d.causes, isNotEmpty, reason: '$code 必须有常见原因');
        expect(d.suggestion, isNotEmpty, reason: '$code 必须有处理建议');
      });
    });

    test('精确码优先于规则推断（已收录的 U 码不走通用网络兜底）', () {
      // U0100 已收录为精确码：标题应为"失去通信"而非规则兜底的"网络通信故障"。
      final u = DtcDatabase.explain('U0100');
      expect(u.isGeneric, isFalse);
      expect(u.title, contains('失去通信'));
      expect(u.title, contains('ECM/PCM'));
      expect(u.title, isNot(contains('网络通信')));
      expect(u.desc, contains('发动机控制模块'));
    });

    test('精确码总量达到 300+ 目标', () {
      expect(DtcDatabase.exactCount, greaterThanOrEqualTo(300),
          reason: '精确字典应扩充到 300+ 条，当前仅 ${DtcDatabase.exactCount}');
    });

    test('lookup 命中返回、未收录返回 null', () {
      expect(DtcDatabase.lookup('P0171'), isNotNull);
      expect(DtcDatabase.lookup('P0999'), isNull);
      // 扩充家族代表码都应可被 lookup 直接命中。
      for (final c in ['P0305', 'P0358', 'P0456', 'P0750', 'P0773', 'U0073', 'B0014']) {
        expect(DtcDatabase.lookup(c), isNotNull, reason: '$c 应在精确字典中');
      }
    });

    test('大小写与空格容错', () {
      expect(DtcDatabase.explain('p0171').title, '第1排混合气过稀');
      expect(DtcDatabase.explain('  p0301 ').title, '第1缸失火');
      expect(DtcDatabase.explain('u0100').title, contains('失去通信'));
    });
  });

  group('DTC 规则兜底（SAE J2012 码位）', () {
    test('未收录的 P 码仍按第 3 位子系统解析（精确未命中才走规则）', () {
      // P0999 未收录 -> 走规则，应为通用变速箱分类。
      final d = DtcDatabase.explain('P0999');
      expect(d.isGeneric, isTrue);
      expect(d.title, contains('变速箱'));
      expect(d.desc, contains('动力总成'));
      expect(d.causes, isNotEmpty);
      expect(d.suggestion, isNotEmpty);
    });

    test('P 码第 2 位为 1 判为厂商自定义码', () {
      final d = DtcDatabase.explain('P1623');
      expect(d.isGeneric, isTrue);
      expect(d.suggestion, contains('厂商自定义'));
    });

    test('未收录的 C/B/U 码按系统分类兜底', () {
      // 这些码不在精确字典中，应走规则兜底；不要与已收录码冲突。
      expect(DtcDatabase.explain('C0235').title, contains('底盘'));
      expect(DtcDatabase.explain('B0100').title, contains('车身'));
      expect(DtcDatabase.explain('U0200').title, contains('网络'));
      for (final c in ['C0235', 'B0100', 'U0200']) {
        final d = DtcDatabase.explain(c);
        expect(d.isGeneric, isTrue, reason: '$c 未收录应走规则兜底');
        expect(d.causes, isNotEmpty, reason: '$c 必须有原因说明');
        expect(d.suggestion, isNotEmpty, reason: '$c 必须有建议');
      }
    });

    test('任意合法码都有完整解释（不留白）', () {
      for (final c in ['P0123', 'P0799', 'C0235', 'B0100', 'U0200']) {
        final d = DtcDatabase.explain(c);
        expect(d.title.trim(), isNotEmpty, reason: '$c title 不能空');
        expect(d.desc.trim(), isNotEmpty, reason: '$c desc 不能空');
        expect(d.suggestion.trim(), isNotEmpty, reason: '$c suggestion 不能空');
      }
    });
  });

  group('DTC 非法 / 扩展码兜底', () {
    test('非法格式不抛异常并给出未识别提示', () {
      for (final raw in ['X1234', 'P12', 'P012A', '', '故障', 'P01']) {
        final d = DtcDatabase.explain(raw);
        expect(d.isGeneric, isTrue);
        expect(d.title, contains('未识别'));
        expect(d.suggestion, isNotEmpty, reason: '非法码 $raw 也必须给建议');
      }
    });
  });
}
