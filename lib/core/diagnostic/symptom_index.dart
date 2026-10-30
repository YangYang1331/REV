/// 症状自查（离线规则库）：用户勾症状 / 输入口语描述 → 给疑似故障码排序。
///
/// 设计原则：**全部在本机算，不上传任何数据、不联网、不调用大模型**。
/// 评分 = 人工整理的"症状 → 码"映射 + 故障码标题/原因/建议里的关键词命中，
/// 命中越多越靠前；同一权重时严重度高的排前面（先处理会烧件的）。
library;

import 'package:obd_dashboard/core/diagnostic/dtc_advice.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';

/// 一个可勾选的症状。
class SymptomDef {
  const SymptomDef(this.id, this.label, this.codes);

  final String id;
  final String label;

  /// 该症状最常见的故障码（按经验整理，不追求穷举）。
  final List<String> codes;
}

/// 一条疑似结果。
class SuspectCode {
  const SuspectCode({
    required this.code,
    required this.score,
    required this.reasons,
  });

  final String code;
  final int score;

  /// 命中理由（症状名 / 关键词），用于向用户解释"凭什么推这个码"。
  final List<String> reasons;

  DtcInfo get info => DtcDatabase.explain(code);
  DtcAdvice get advice => DtcAdvice.of(code);
}

class SymptomIndex {
  const SymptomIndex._();

  /// 常见症状（口语化，覆盖国内用户最常搜的说法）。
  static const List<SymptomDef> symptoms = [
    SymptomDef('shake_idle', '怠速抖动 / 等红灯抖', [
      'P0300', 'P0301', 'P0302', 'P0303', 'P0304', 'P0171', 'P0505',
    ]),
    SymptomDef('hard_start', '冷车难启动 / 打不着火', [
      'P0335', 'P0340', 'P0230', 'P0122', 'P0118', 'P0171',
    ]),
    SymptomDef('no_power', '加速无力 / 提速肉', [
      'P0171', 'P0420', 'P0101', 'P0299', 'P0011', 'P0087',
    ]),
    SymptomDef('high_fuel', '油耗明显变高', [
      'P0171', 'P0172', 'P0420', 'P0101', 'P0113', 'P0128',
    ]),
    SymptomDef('misfire', '发动机抖 + 故障灯闪', [
      'P0300', 'P0301', 'P0302', 'P0303', 'P0304', 'P0305', 'P0306',
    ]),
    SymptomDef('stall', '行驶中熄火 / 悠车', [
      'P0335', 'P0101', 'P0171', 'P0505', 'P2101', 'P2135',
    ]),
    SymptomDef('white_smoke', '排气冒白烟 / 蓝烟', [
      'P0300', 'P0420', 'P0128', 'P0118',
    ]),
    SymptomDef('black_smoke', '排气冒黑烟 / 尾气刺鼻', [
      'P0172', 'P0101', 'P0420', 'P0401',
    ]),
    SymptomDef('cat_smell', '尾气有臭鸡蛋味', ['P0420', 'P0430', 'P0171']),
    SymptomDef('evap', '加完油闻到汽油味 / 油箱盖报警', [
      'P0455', 'P0456', 'P0442', 'P0440',
    ]),
    SymptomDef('idle_high', '怠速偏高不下来', [
      'P0507', 'P0505', 'P0121', 'P0113',
    ]),
    SymptomDef('temp_high', '水温偏高 / 开锅', ['P0128', 'P0118', 'P0217', 'P0480']),
    SymptomDef('battery', '启动无力 / 电压不稳', [
      'P0562', 'P0563', 'P0620', 'P2503',
    ]),
    SymptomDef('egr', '怠速不稳 + 加速顿挫（EGR 怀疑）', [
      'P0401', 'P0402', 'P0404', 'P0405',
    ]),
    SymptomDef('o2', '混合气偏稀 / 偏浓报警', ['P0171', 'P0172', 'P0130', 'P0135', 'P0141']),
    SymptomDef('vvt', '冷启动有"咔咔"响 / 动力迟滞', [
      'P0011', 'P0012', 'P0016', 'P0340',
    ]),
    SymptomDef('trans', '换挡顿挫 / 挡位不升', ['P0700', 'P0715', 'P0720', 'P0730']),
    SymptomDef('abs_light', 'ABS 灯亮', ['C0035', 'C0040', 'C0050', 'C0110']),
    SymptomDef('tpms', '胎压灯亮 / 漏气', ['C0750', 'C0755', 'C0760', 'C0765']),
    SymptomDef('coolant_loss', '防冻液少得快', ['P0128', 'P0118', 'P0480']),
    SymptomDef('knock', '急加速有爆震敲缸声', ['P0325', 'P0330', 'P0300']),
    SymptomDef('dpf', '柴油车动力受限 / 再生频繁', [
      'P2002', 'P2463', 'P2458', 'P0401',
    ]),
  ];

  /// 按勾选的症状 + 自由文本，返回排序后的疑似码（最多 [limit] 条）。
  static List<SuspectCode> match({
    Set<String> symptomIds = const {},
    String freeText = '',
    int limit = 8,
  }) {
    final scores = <String, int>{};
    final reasons = <String, List<String>>{};

    void hit(String code, int weight, String why) {
      final c = code.toUpperCase();
      scores[c] = (scores[c] ?? 0) + weight;
      final r = reasons.putIfAbsent(c, () => <String>[]);
      if (!r.contains(why)) r.add(why);
    }

    for (final s in symptoms) {
      if (!symptomIds.contains(s.id)) continue;
      // 首个码权重更高：是这条症状最典型的码。
      for (var i = 0; i < s.codes.length; i++) {
        hit(s.codes[i], i == 0 ? 4 : 3, s.label);
      }
    }

    final text = freeText.trim();
    if (text.isNotEmpty) {
      final tokens = _tokens(text);
      // 1) 复述到症状标签上：把症状映射一并算进来
      for (final s in symptoms) {
        for (final t in tokens) {
          if (t.length >= 2 && s.label.contains(t)) {
            for (final c in s.codes.take(4)) {
              hit(c, 2, '描述匹配「${s.label}」');
            }
          }
        }
      }
      // 2) 直接匹配故障码释义（标题 / 说明 / 原因）
      for (final code in DtcDatabase.codes) {
        final info = DtcDatabase.lookup(code);
        if (info == null) continue;
        final hay = '${info.title} ${info.desc} ${info.causes.join(' ')}';
        for (final t in tokens) {
          if (t.length < 2) continue;
          if (hay.contains(t)) {
            hit(code, 2, '释义含「$t」');
            break;
          }
        }
      }
    }

    final out = scores.entries
        .map((e) => SuspectCode(
              code: e.key,
              score: e.value,
              reasons: reasons[e.key] ?? const [],
            ))
        .toList()
      ..sort((a, b) {
        final s = b.score.compareTo(a.score);
        if (s != 0) return s;
        final sev = b.advice.severity.compareTo(a.advice.severity);
        if (sev != 0) return sev;
        return a.code.compareTo(b.code);
      });
    return out.take(limit).toList(growable: false);
  }

  /// 中文没有空格，按标点/空白切分；再补一些两字滑窗，提高召回。
  static List<String> _tokens(String s) {
    final parts = s
        .split(RegExp('[\\s,，。、;；:：!！?？/|()（）\\[\\]【】"“”\'’]+'))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toList();
    final out = <String>[];
    for (final p in parts) {
      if (p.length <= 6) {
        out.add(p);
      } else {
        // 长句拆成 2~4 字的滑窗，避免整句永远匹配不上
        for (var i = 0; i + 2 <= p.length; i += 2) {
          out.add(p.substring(i, i + 2));
        }
      }
    }
    return out;
  }
}
