/// 发动机型号档案 + 用户调音参数（v2.17.6）。
///
/// 纯 Dart、无插件依赖，供合成声浪与采样包选择页共用：
///  - [EngineProfile]：几缸、几冲程点火次数、各阶谐波权重（怠速/高转两套），
///    决定了「这台引擎该是什么味道」；
///  - [EngineTuning]：用户可调的亮度 / 低频厚度 / 颗粒感 / 回火量。
///
/// 物理依据：四冲程每两转完成一次点火循环，
/// 点火频率 f_fire = rpm / 60 × (缸数 / 2) = rpm / 60 × 每转点火次数。
/// 合成声浪的基频就取 f_fire，转速升高 → 点火更密 → 音调线性升高。
library;

import 'dart:math' as math;

/// 参与合成的阶次（相对点火频率的倍数）。
/// 0.5x 是曲轴半阶（V8 的「咕噜」来源），6x/8x 提供金属亮感。
const List<double> kEngineOrders = [0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0];

/// 引擎布局（只影响文案与调音倾向，不参与运算）。
enum EngineLayout { inline, v, flat, rotary }

/// 一台引擎的性格档案。
class EngineProfile {
  const EngineProfile({
    required this.id,
    required this.name,
    required this.cylinders,
    required this.pulsesPerRev,
    required this.layout,
    required this.idleWeights,
    required this.highWeights,
    this.vAngleDeg = 0,
    this.noiseIdle = 0.10,
    this.noiseHigh = 0.42,
    this.roughness = 0.5,
    this.hasPop = true,
    this.hasBlowoff = false,
    this.note = '',
  });

  final String id;
  final String name;

  /// 缸数（转子为转子数×3 个工作面）。
  final int cylinders;

  /// 曲轴每转点火次数（四冲程 = 缸数/2；转子按工作面计）。
  final int pulsesPerRev;

  final EngineLayout layout;
  final double vAngleDeg;

  /// 阶次 → 权重（0..1），怠速与高转两套，中间按转带线性插值。
  final Map<double, double> idleWeights;
  final Map<double, double> highWeights;

  /// 排气噪声层电平（怠速 / 高转）。
  final double noiseIdle;
  final double noiseHigh;

  /// 粗糙度：越高越适合加颗粒（失真），也越「炸」。
  final double roughness;

  final bool hasPop;
  final bool hasBlowoff;

  /// 选择页副标题。
  final String note;

  /// 点火频率（Hz）。rpm 非法时返回 0。
  double firingHz(double rpm) {
    if (!rpm.isFinite || rpm <= 0) return 0;
    return rpm / 60.0 * pulsesPerRev;
  }

  static EngineProfile byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return i4;
  }

  /// 采样包 → 引擎档案（用于包列表文案/回火参数；合成模式由用户选择）。
  static EngineProfile forPack(String packId) => switch (packId) {
        'bmw_s58' => i6,
        'amg_c63' || 'ls_v8' || 'mustang_gt' || 'corvette_c8' =>
          v8,
        'hellcat_supercharged' => v8,
        'lambo_v10' || 'audi_r8' || 'lexus_lfa' || 'dodge_viper' => v10,
        'v12' || 'video_aventador_v12' => v12,
        'subaru_sti' => h4,
        'porsche_gt3' || 'porsche_turbo' => h6,
        'mazda_rotary' || 'video_rx8_rotary' => rotary,
        _ => i4,
      };

  static final EngineProfile i4 = EngineProfile(
    id: 'i4',
    name: '直列四缸',
    cylinders: 4,
    pulsesPerRev: 2,
    layout: EngineLayout.inline,
    idleWeights: {
      0.5: 0.55, 1.0: 0.90, 2.0: 0.75, 3.0: 0.40,
      4.0: 0.32, 6.0: 0.18, 8.0: 0.10,
    },
    highWeights: {
      0.5: 0.15, 1.0: 0.58, 2.0: 0.85, 3.0: 0.78,
      4.0: 0.52, 6.0: 0.32, 8.0: 0.20,
    },
    note: '点火均匀、底子单薄，高转清脆',
  );

  static final EngineProfile i6 = EngineProfile(
    id: 'i6',
    name: '直列六缸',
    cylinders: 6,
    pulsesPerRev: 3,
    layout: EngineLayout.inline,
    idleWeights: {
      0.5: 0.32, 1.0: 0.86, 2.0: 0.58, 3.0: 0.46,
      4.0: 0.30, 6.0: 0.22, 8.0: 0.12,
    },
    highWeights: {
      0.5: 0.10, 1.0: 0.70, 2.0: 0.80, 3.0: 0.62,
      4.0: 0.46, 6.0: 0.34, 8.0: 0.22,
    },
    noiseIdle: 0.08,
    noiseHigh: 0.36,
    roughness: 0.35,
    note: '丝滑线性，高转优雅不粗暴',
  );

  static final EngineProfile v6 = EngineProfile(
    id: 'v6',
    name: 'V6',
    cylinders: 6,
    pulsesPerRev: 3,
    layout: EngineLayout.v,
    vAngleDeg: 60,
    idleWeights: {
      0.5: 0.45, 1.0: 0.82, 2.0: 0.66, 3.0: 0.42,
      4.0: 0.30, 6.0: 0.20, 8.0: 0.12,
    },
    highWeights: {
      0.5: 0.14, 1.0: 0.66, 2.0: 0.82, 3.0: 0.66,
      4.0: 0.48, 6.0: 0.30, 8.0: 0.18,
    },
    note: '兼顾浑厚与灵动',
  );

  static final EngineProfile v8 = EngineProfile(
    id: 'v8',
    name: 'V8 十字曲轴',
    cylinders: 8,
    pulsesPerRev: 4,
    layout: EngineLayout.v,
    vAngleDeg: 90,
    idleWeights: {
      0.5: 0.92, 1.0: 0.80, 2.0: 0.72, 3.0: 0.24,
      4.0: 0.50, 6.0: 0.15, 8.0: 0.08,
    },
    highWeights: {
      0.5: 0.34, 1.0: 0.74, 2.0: 0.88, 3.0: 0.45,
      4.0: 0.60, 6.0: 0.30, 8.0: 0.16,
    },
    noiseIdle: 0.14,
    noiseHigh: 0.44,
    roughness: 0.6,
    note: '低频厚、怠速咕噜，余音长',
  );

  static final EngineProfile v10 = EngineProfile(
    id: 'v10',
    name: 'V10',
    cylinders: 10,
    pulsesPerRev: 5,
    layout: EngineLayout.v,
    vAngleDeg: 90,
    idleWeights: {
      0.5: 0.28, 1.0: 0.70, 2.0: 0.60, 3.0: 0.50,
      4.0: 0.44, 6.0: 0.34, 8.0: 0.24,
    },
    highWeights: {
      0.5: 0.10, 1.0: 0.64, 2.0: 0.84, 3.0: 0.80,
      4.0: 0.70, 6.0: 0.50, 8.0: 0.36,
    },
    noiseIdle: 0.10,
    noiseHigh: 0.50,
    roughness: 0.7,
    note: '金属撕裂感，短促爆发',
  );

  static final EngineProfile v12 = EngineProfile(
    id: 'v12',
    name: 'V12',
    cylinders: 12,
    pulsesPerRev: 6,
    layout: EngineLayout.v,
    vAngleDeg: 60,
    idleWeights: {
      0.5: 0.24, 1.0: 0.80, 2.0: 0.66, 3.0: 0.50,
      4.0: 0.40, 6.0: 0.30, 8.0: 0.20,
    },
    highWeights: {
      0.5: 0.08, 1.0: 0.70, 2.0: 0.76, 3.0: 0.62,
      4.0: 0.52, 6.0: 0.40, 8.0: 0.28,
    },
    noiseIdle: 0.07,
    noiseHigh: 0.34,
    roughness: 0.25,
    note: '绵密顺滑、层次丰富',
  );

  static final EngineProfile h4 = EngineProfile(
    id: 'h4',
    name: '水平对置四缸',
    cylinders: 4,
    pulsesPerRev: 2,
    layout: EngineLayout.flat,
    idleWeights: {
      0.5: 0.80, 1.0: 0.86, 2.0: 0.62, 3.0: 0.30,
      4.0: 0.32, 6.0: 0.16, 8.0: 0.09,
    },
    highWeights: {
      0.5: 0.24, 1.0: 0.70, 2.0: 0.80, 3.0: 0.56,
      4.0: 0.46, 6.0: 0.28, 8.0: 0.16,
    },
    noiseIdle: 0.12,
    noiseHigh: 0.46,
    roughness: 0.65,
    note: '拳击手脉冲，独特跳动感',
  );

  static final EngineProfile h6 = EngineProfile(
    id: 'h6',
    name: '水平对置六缸',
    cylinders: 6,
    pulsesPerRev: 3,
    layout: EngineLayout.flat,
    idleWeights: {
      0.5: 0.40, 1.0: 0.84, 2.0: 0.56, 3.0: 0.48,
      4.0: 0.32, 6.0: 0.24, 8.0: 0.14,
    },
    highWeights: {
      0.5: 0.12, 1.0: 0.68, 2.0: 0.80, 3.0: 0.66,
      4.0: 0.50, 6.0: 0.38, 8.0: 0.24,
    },
    noiseIdle: 0.09,
    noiseHigh: 0.38,
    roughness: 0.4,
    note: '高转嘶吼带金属亮感',
  );

  static final EngineProfile rotary = EngineProfile(
    id: 'rotary',
    name: '转子（双转子）',
    cylinders: 6,
    pulsesPerRev: 6,
    layout: EngineLayout.rotary,
    idleWeights: {
      0.5: 0.55, 1.0: 1.00, 2.0: 0.90, 3.0: 0.70,
      4.0: 0.50, 6.0: 0.44, 8.0: 0.30,
    },
    highWeights: {
      0.5: 0.18, 1.0: 0.95, 2.0: 0.86, 3.0: 0.78,
      4.0: 0.62, 6.0: 0.55, 8.0: 0.40,
    },
    noiseIdle: 0.06,
    noiseHigh: 0.30,
    roughness: 0.3,
    hasPop: true,
    note: '连续旋转燃烧，持续啸叫',
  );

  static final List<EngineProfile> all = [
    i4, i6, v6, v8, v10, v12, h4, h6, rotary,
  ];
}

/// 用户调音参数（全部 0..1 之外的量在构造时钳位）。
class EngineTuning {
  const EngineTuning({
    this.brightness = 1.0,
    this.lowEnd = 1.0,
    this.grit = 0.35,
    this.popAmount = 0.6,
  });

  /// 高频亮度：>1 提 2 阶以上谐波，<1 变闷。
  final double brightness;

  /// 低频厚度：>1 加厚 1 阶以下，<1 变干净。
  final double lowEnd;

  /// 颗粒/失真：0 = 顺滑，1 = 炸裂。
  final double grit;

  /// 回火放炮量：0 = 关闭，1 = 频繁。
  final double popAmount;

  EngineTuning copyWith({
    double? brightness,
    double? lowEnd,
    double? grit,
    double? popAmount,
  }) =>
      EngineTuning(
        brightness: (brightness ?? this.brightness).clamp(0.6, 1.6),
        lowEnd: (lowEnd ?? this.lowEnd).clamp(0.5, 1.6),
        grit: (grit ?? this.grit).clamp(0.0, 1.0),
        popAmount: (popAmount ?? this.popAmount).clamp(0.0, 1.0),
      );

  /// 高阶谐波增益倍数（阶次越高受影响越大）。
  double highOrderScale(double order) =>
      order >= 2.0 ? math.pow(brightness, (order - 1) / 3.0).toDouble() : 1.0;

  /// 低阶（0.5x/1x）增益倍数。
  double lowOrderScale(double order) =>
      order < 2.0 ? lowEnd : 1.0;

  static EngineTuning fromJson(Map<String, dynamic>? j) {
    if (j == null) return const EngineTuning();
    double read(String k, double d) {
      final v = j[k];
      if (v is num && v.isFinite) return v.toDouble();
      return d;
    }

    return const EngineTuning().copyWith(
      brightness: read('b', 1.0),
      lowEnd: read('l', 1.0),
      grit: read('g', 0.35),
      popAmount: read('p', 0.6),
    );
  }

  Map<String, dynamic> toJson() => {
        'b': brightness,
        'l': lowEnd,
        'g': grit,
        'p': popAmount,
      };
}
