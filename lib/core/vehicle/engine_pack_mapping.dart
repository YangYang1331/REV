/// 多引擎采样包「rpm → band 循环权重 + one-shot 触发」纯逻辑层（v2.11.0）。
///
/// 不依赖任何音频插件/平台，全部决策在此算好，平台层（EngineSoundService）
/// 按 50ms pump 下发；单测不依赖真实采样文件存在。
library;

import 'dart:math' as math;

/// 一个引擎采样包的 manifest 描述（对应 assets/audio/packs/manifest.json）。
class EnginePackManifest {
  const EnginePackManifest({
    required this.id,
    required this.name,
    this.turbo = false,
    this.supercharged = false,
    this.bands = const ['idle', 'low', 'mid', 'high', 'bounce'],
    this.hasPop = false,
    this.hasBlowoff = false,
    this.hasWhine = false,
    this.synthOnly = false,
    this.core = 'idle',
    this.toneHz = 9000,
    this.profileId,
  });

  final String id;
  final String name;

  /// 涡轮：松油播泄压阀 one_blowoff。
  final bool turbo;

  /// 机械增压：转速上升时 one_whine 渐强。
  final bool supercharged;

  /// 循环段 band id 列表。
  final List<String> bands;

  /// 是否含放炮/偏时点火 one_pop。
  final bool hasPop;
  final bool hasBlowoff;
  final bool hasWhine;

  /// 仅合成（即 "synth" 包本身，无采样文件）。
  final bool synthOnly;

  /// 主循环段（v2.17.7）：每包只播这一段，靠连续变调跟随转速，
  /// 不再多段交叉淡化（多段是同一段录音的重复，叠播会产生梳状/合唱感）。
  final String core;

  /// 采样音色低通截止（Hz）：录音本身的高频嘶声/风噪在这里收掉。
  final double toneHz;

  /// 固定引擎档案（v2.17.8）：选中该包时把合成档案切到它。
  /// 只用于「实时合成」类的整车预设（如领克 03+），采样包为 null。
  final String? profileId;

  static EnginePackManifest fromJson(Map<String, dynamic> j) =>
      EnginePackManifest(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        turbo: j['turbo'] == true,
        supercharged: j['supercharged'] == true,
        bands: (j['bands'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        hasPop: j['hasPop'] == true,
        hasBlowoff: j['hasBlowoff'] == true,
        hasWhine: j['hasWhine'] == true,
        synthOnly: j['synthOnly'] == true,
        core: (j['core']?.toString().trim().isNotEmpty ?? false)
            ? j['core'].toString()
            : 'idle',
        toneHz: (j['toneHz'] as num?)?.toDouble() ?? 9000,
        profileId: (j['profile']?.toString().trim().isNotEmpty ?? false)
            ? j['profile'].toString().trim()
            : null,
      );
}

/// 各 band 循环的目标音量权重（0..1）。bounce 是叠加效果、不归一化。
class EngineBandWeights {
  const EngineBandWeights({
    required this.idle,
    required this.low,
    required this.mid,
    required this.high,
    this.bounce = 0,
  });

  final double idle;
  final double low;
  final double mid;
  final double high;

  /// 收油（高转掉转速）时叠加的 bounce 段权重。
  final double bounce;

  double operator [](String band) => switch (band) {
        'idle' => idle,
        'low' => low,
        'mid' => mid,
        'high' => high,
        'bounce' => bounce,
        _ => 0,
      };
}

/// 把 rpm 映射到相邻 band 循环的交叉淡化权重。
///
/// 归一化转带 t = (rpm-idle)/(redline-idle)，钳到 [0,1]；
/// idle/low/mid/high 四段用三角窗（中心 0.06/0.26/0.575/0.875，半宽 0.175），
/// 过渡区相邻两段线性此消彼长；权重归一化使总响度恒定，杜绝换段跳变。
class EngineBandPlanner {
  const EngineBandPlanner();

  static const _centers = {'idle': 0.06, 'low': 0.26, 'mid': 0.575, 'high': 0.875};
  static const _halfW = 0.175;

  EngineBandWeights plan(double rpm, double idleRpm, double redlineRpm) {
    final span = (redlineRpm - idleRpm).abs();
    var t = span <= 0 ? 0.0 : (rpm - idleRpm) / span;
    t = t.clamp(0.0, 1.0);

    double triangle(String band) {
      final c = _centers[band]!;
      final d = (t - c).abs();
      if (d >= _halfW) return 0;
      return 1.0 - d / _halfW;
    }

    var idle = triangle('idle');
    var low = triangle('low');
    var mid = triangle('mid');
    var high = triangle('high');

    // 归一化（bounce 不参与归一化）。
    final sum = idle + low + mid + high;
    if (sum > 1e-6) {
      idle /= sum;
      low /= sum;
      mid /= sum;
      high /= sum;
    } else {
      idle = 1;
    }
    return EngineBandWeights(idle: idle, low: low, mid: mid, high: high);
  }

  /// 收油 bounce 叠加权重：转速快降（>2500 rpm/s）且 rpm 已脱离怠速带时
  /// 随掉转速度渐强，最高 1。
  double bounceWeight(
      double drpmPerSec, double rpm, double idleRpm) {
    if (drpmPerSec >= -2500) return 0;
    if (rpm < idleRpm * 1.5) return 0;
    return ((-drpmPerSec - 2500) / 3000).clamp(0.0, 1.0);
  }

  /// 某 band 循环在归一化转带 t 下的播放速度（同 band 内连续变调，
  /// 让匀速驾驶不再是"固定录音"）。pos=((t-center)/halfW) clamp(-1..1)。
  /// 非 idle 映射 0.80~1.20；idle 只小幅 0.94~1.06（怠速音高别大摆）；
  /// bounce 固定 1.0（收油叠加段，不参与变调以免发尖）。
  double bandPlaySpeed({required String band, required double t}) {
    final tt = t.clamp(0.0, 1.0);
    if (band == 'bounce') return 1.0;
    final c = _centers[band];
    if (c == null) return 1.0;
    final pos = ((tt - c) / _halfW).clamp(-1.0, 1.0);
    if (band == 'idle') return 1.0 + pos * 0.06;
    return 1.0 + pos * 0.20;
  }
}

/// 采样包核心循环的播放倍速（v2.17.7）。
///
/// 每个包只播一段核心录音，录音自身所在转速带（[coreBand] = idle/low/mid）
/// 对应倍速 1.0；怠速时按带位下调、红线时升到 1.85 倍。
/// 曲线单调递增，保证「转速越高音调越尖」听得出来，且不出现极端变调。
double corePlaySpeed({
  required String coreBand,
  required double rpm,
  required double idleRpm,
  required double redlineRpm,
}) {
  final span = (redlineRpm - idleRpm).abs();
  final t = span <= 0 ? 0.0 : ((rpm - idleRpm) / span).clamp(0.0, 1.0);
  final tCore = switch (coreBand) {
    'low' => 0.25,
    'mid' => 0.55,
    _ => 0.0,
  };
  final idleSpeed = 1.0 - 0.32 * (tCore / 0.55);
  if (t <= tCore) {
    return tCore <= 0 ? 1.0 : idleSpeed + (1.0 - idleSpeed) * (t / tCore);
  }
  return 1.0 + 0.85 * ((t - tCore) / (1.0 - tCore));
}

/// 本帧该播哪几个 one-shot（放炮/泄压/机增啸叫）。
enum EngineOneShot { pop, blowoff, whine }

/// one-shot 触发决策器（纯逻辑、带状态、可注入随机源与时钟）。
///
/// 规则（评审契约）：
///  - pop：drpm < -1500 rpm/s 且 rpm > 3000，最小间隔 500ms，概率触发；
///  - blowoff：包 turbo=true、drpm < -1000 且 rpm > 2000，最小间隔 800ms；
///  - whine：包 supercharged=true 且 drpm > 800（爬升），最小间隔 1000ms。
class EngineOneShotDecider {
  EngineOneShotDecider({
    this.popMinIntervalMs = 500,
    this.blowoffMinIntervalMs = 800,
    this.whineMinIntervalMs = 1000,
    this.popProbability = 0.6,
    double Function()? random,
  }) : _random = random ?? _defaultRandom;

  final int popMinIntervalMs;
  final int blowoffMinIntervalMs;
  final int whineMinIntervalMs;
  final double popProbability;
  final double Function() _random;

  int? _lastPopAt;
  int? _lastBlowoffAt;
  int? _lastWhineAt;

  static double _defaultRandom() => math.Random().nextDouble();

  void reset() {
    _lastPopAt = null;
    _lastBlowoffAt = null;
  }

  List<EngineOneShot> decide({
    required double rpm,
    required double drpmPerSec,
    required int nowMs,
    required EnginePackManifest pack,
  }) {
    final out = <EngineOneShot>[];

    // 放炮/偏时：高转骤降。
    if (pack.hasPop &&
        drpmPerSec < -1500 &&
        rpm > 3000 &&
        (nowMs - (_lastPopAt ?? -100000) >= popMinIntervalMs) &&
        _random() < popProbability) {
      _lastPopAt = nowMs;
      out.add(EngineOneShot.pop);
    }

    // 涡轮泄压：松油。
    if (pack.turbo &&
        pack.hasBlowoff &&
        drpmPerSec < -1000 &&
        rpm > 2000 &&
        (nowMs - (_lastBlowoffAt ?? -100000) >= blowoffMinIntervalMs)) {
      _lastBlowoffAt = nowMs;
      out.add(EngineOneShot.blowoff);
    }

    // 机增啸叫：爬升。
    if (pack.supercharged &&
        pack.hasWhine &&
        drpmPerSec > 800 &&
        (nowMs - (_lastWhineAt ?? -100000) >= whineMinIntervalMs)) {
      _lastWhineAt = nowMs;
      out.add(EngineOneShot.whine);
    }

    return out;
  }
}

/// 音质档位：auto=按构建变体+位数自动；high=强制 hi；low=强制 lo。
enum AudioQuality { auto, high, low }

AudioQuality parseAudioQuality(String? s) => switch (s) {
      'high' => AudioQuality.high,
      'low' => AudioQuality.low,
      _ => AudioQuality.auto,
    };

/// 采样档位三因子选择：构建变体 + 进程位数 + 用户音质档位。
///  - quality=high → 强制 hi；quality=low → 强制 lo；
///  - quality=auto：variant='car'（车机包）无论 32/64 位都 lo；
///    variant='phone'：64 位 hi，32 位老手机 lo。
String sampleBit({
  required String variant,
  required bool is32bit,
  AudioQuality quality = AudioQuality.auto,
}) {
  if (quality == AudioQuality.high) return 'hi';
  if (quality == AudioQuality.low) return 'lo';
  if (variant == 'car') return 'lo';
  return is32bit ? 'lo' : 'hi';
}

/// 按持久化 packId 在 manifest 列表里解析当前包；找不到/为空 → 退回 synth。
/// （纯函数：冷启动未加载 manifest 时也安全，绝不抛 StateError。）
EnginePackManifest resolveEnginePack(
    String packId, List<EnginePackManifest> packs) {
  for (final p in packs) {
    if (p.id == packId) return p;
  }
  return const EnginePackManifest(
      id: 'synth', name: '合成引擎 · 可调', synthOnly: true);
}

/// 采样包分类（选择页分组用）。
enum EnginePackGroup { na, turbo, supercharged, rotary, synth }

EnginePackGroup enginePackGroup(EnginePackManifest p) {
  // 固定档案的合成预设（如领克 03+）按动力属性归组，其余 synthOnly 归合成组。
  if (p.id == 'synth' || (p.synthOnly && p.profileId == null)) {
    return EnginePackGroup.synth;
  }
  if (p.supercharged) return EnginePackGroup.supercharged;
  if (p.id.contains('rotary')) return EnginePackGroup.rotary;
  if (p.turbo) return EnginePackGroup.turbo;
  return EnginePackGroup.na;
}

String enginePackGroupLabel(EnginePackGroup g) => switch (g) {
      EnginePackGroup.na => '自然吸气',
      EnginePackGroup.turbo => '涡轮增压',
      EnginePackGroup.supercharged => '机械增压',
      EnginePackGroup.rotary => '转子',
      EnginePackGroup.synth => '合成引擎（可调）',
    };
