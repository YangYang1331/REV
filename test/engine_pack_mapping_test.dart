import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/vehicle/engine_pack_mapping.dart';

void main() {
  const planner = EngineBandPlanner();

  group('band 三角交叉淡化权重', () {
    test('怠速带 idle 权重≈1', () {
      final w = planner.plan(800, 800, 6500);
      expect(w.idle, greaterThan(0.9));
      expect(w.high, 0);
    });

    test('红线 high 权重≈1', () {
      final w = planner.plan(6500, 800, 6500);
      expect(w.high, greaterThan(0.9));
      expect(w.idle, 0);
    });

    test('过渡区相邻两段此消彼长、总和≈1', () {
      // idle→low 边界 t=0.12 附近
      final w = planner.plan(800 + (6500 - 800) * 0.12, 800, 6500);
      final sum = w.idle + w.low + w.mid + w.high;
      expect(sum, closeTo(1.0, 0.02));
      expect(w.idle, greaterThan(0.1));
      expect(w.low, greaterThan(0.1));
    });

    test('归一化后任意 rpm 总权重≈1', () {
      for (var rpm = 800; rpm <= 6500; rpm += 300) {
        final w = planner.plan(rpm.toDouble(), 800, 6500);
        final sum = w.idle + w.low + w.mid + w.high;
        expect(sum, closeTo(1.0, 0.02), reason: 'rpm=$rpm');
      }
    });

    test('bounce：高转骤降才叠加', () {
      // 慢掉转 → 0
      expect(planner.bounceWeight(-1000, 4000, 800), 0);
      // 快掉转但已接近怠速 → 0
      expect(planner.bounceWeight(-5000, 1000, 800), 0);
      // 高转快掉 → >0
      final b = planner.bounceWeight(-5000, 4500, 800);
      expect(b, greaterThan(0.2));
    });
  });

  group('one-shot 触发决策', () {
  const turboPack = EnginePackManifest(
      id: 't',
      name: 't',
      turbo: true,
      supercharged: true,
      hasPop: true,
      hasBlowoff: true,
      hasWhine: true,
    );
    const naPack = EnginePackManifest(
      id: 'na',
      name: 'na',
      turbo: false,
      hasPop: true,
    );

    test('放炮：高转骤降 + 概率内触发；低转不触发', () {
      final d = EngineOneShotDecider(random: () => 0.1); // 总是命中概率
      final hits = d.decide(
          rpm: 4500, drpmPerSec: -3000, nowMs: 0, pack: turboPack);
      expect(hits, contains(EngineOneShot.pop));
      // 低转（rpm<3000）不触发
      final low = d.decide(
          rpm: 2000, drpmPerSec: -3000, nowMs: 1000, pack: turboPack);
      expect(low.contains(EngineOneShot.pop), false);
    });

    test('放炮最小间隔 500ms：连发被节流', () {
      final d = EngineOneShotDecider(random: () => 0.0);
      d.decide(rpm: 4500, drpmPerSec: -3000, nowMs: 0, pack: turboPack);
      final again = d.decide(
          rpm: 4500, drpmPerSec: -3000, nowMs: 200, pack: turboPack);
      expect(again.contains(EngineOneShot.pop), false);
    });

    test('泄压阀：仅 turbo 包在松油时触发', () {
      final dTurbo = EngineOneShotDecider();
      final hits = dTurbo.decide(
          rpm: 3000, drpmPerSec: -2000, nowMs: 0, pack: turboPack);
      expect(hits, contains(EngineOneShot.blowoff));

      final dNa = EngineOneShotDecider();
      final na = dNa.decide(
          rpm: 3000, drpmPerSec: -2000, nowMs: 0, pack: naPack);
      expect(na.contains(EngineOneShot.blowoff), false);
    });

    test('机增啸叫：supercharged 且爬升时触发', () {
      final d = EngineOneShotDecider();
      final hits = d.decide(
          rpm: 2500, drpmPerSec: 2000, nowMs: 0, pack: turboPack);
      expect(hits, contains(EngineOneShot.whine));

      final dNa = EngineOneShotDecider();
      final na = dNa.decide(
          rpm: 2500, drpmPerSec: 2000, nowMs: 0, pack: naPack);
      expect(na.contains(EngineOneShot.whine), false);
    });
  });

  group('hi/lo 档位（构建变体 + 位数 + 音质档）', () {
    test('auto：车机包 car 无论 32/64 位都 lo', () {
      expect(sampleBit(variant: 'car', is32bit: false), 'lo');
      expect(sampleBit(variant: 'car', is32bit: true), 'lo');
    });
    test('auto：手机包 phone 64 位 hi，32 位 lo', () {
      expect(sampleBit(variant: 'phone', is32bit: false), 'hi');
      expect(sampleBit(variant: 'phone', is32bit: true), 'lo');
    });
    test('high 档强制 hi（车机/32 位也 hi，加载失败再回退 lo）', () {
      expect(sampleBit(variant: 'car', is32bit: true, quality: AudioQuality.high),
          'hi');
      expect(sampleBit(
          variant: 'phone', is32bit: true, quality: AudioQuality.high), 'hi');
    });
    test('low 档强制 lo', () {
      expect(sampleBit(variant: 'car', is32bit: false, quality: AudioQuality.low),
          'lo');
      expect(sampleBit(
          variant: 'phone', is32bit: false, quality: AudioQuality.low), 'lo');
    });
    test('parseAudioQuality 容错', () {
      expect(parseAudioQuality('high'), AudioQuality.high);
      expect(parseAudioQuality('low'), AudioQuality.low);
      expect(parseAudioQuality(null), AudioQuality.auto);
      expect(parseAudioQuality('garbage'), AudioQuality.auto);
    });
  });

  group('band 内连续变调 bandPlaySpeed', () {
    const planner = EngineBandPlanner();
    test('同 band 内 t 增大 → 速度单调升高（转速起来声音变尖）', () {
      double prev = 0.5;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final s = planner.bandPlaySpeed(band: 'mid', t: t);
        expect(s, inExclusiveRange(0.79, 1.21));
        if (t > 0.2) expect(s, greaterThan(prev - 1e-9));
        prev = s;
      }
    });
    test('idle 带音高小幅摆动（0.94~1.06），不大起大落', () {
      for (var t = 0.0; t <= 1.0; t += 0.1) {
        final s = planner.bandPlaySpeed(band: 'idle', t: t);
        expect(s, inExclusiveRange(0.93, 1.07));
      }
    });
    test('bounce 固定 1.0（收油叠加段不发尖）', () {
      for (var t = 0.0; t <= 1.0; t += 0.1) {
        expect(planner.bandPlaySpeed(band: 'bounce', t: t), closeTo(1.0, 1e-9));
      }
    });
  });

  test('manifest.fromJson 解析', () {
    final p = EnginePackManifest.fromJson(const {
      'id': 'mazda6_na',
      'name': '马自达6 2.0L 自吸',
      'turbo': false,
      'supercharged': false,
      'hasPop': true,
      'bands': ['idle', 'low', 'mid', 'high'],
    });
    expect(p.id, 'mazda6_na');
    expect(p.hasPop, true);
    expect(p.synthOnly, false);
    // v2.17.7 新增字段的默认值。
    expect(p.core, 'idle');
    expect(p.toneHz, 9000);
    expect(p.profileId, isNull);
  });

  test('manifest.fromJson 解析固定档案预设（领克 03+）', () {
    final p = EnginePackManifest.fromJson(const {
      'id': 'lynk_03',
      'name': '领克 03+ 2.0T',
      'turbo': true,
      'synthOnly': true,
      'bands': [],
      'profile': 'lynk03',
    });
    expect(p.synthOnly, true);
    expect(p.profileId, 'lynk03');
    // 带档案的合成预设按动力属性归组，而不是塞进「合成引擎（可调）」。
    expect(enginePackGroup(p), EnginePackGroup.turbo);
  });

  group('核心循环变调曲线（v2.17.7）', () {
    test('转速升高 → 倍速单调升高（能听出转速变化）', () {
      for (final core in ['idle', 'low', 'mid']) {
        var prev = 0.0;
        for (var rpm = 800.0; rpm <= 6500; rpm += 200) {
          final s = corePlaySpeed(
              coreBand: core, rpm: rpm, idleRpm: 800, redlineRpm: 6500);
          expect(s, greaterThanOrEqualTo(prev - 1e-9), reason: '$core $rpm');
          prev = s;
        }
      }
    });

    test('倍速范围受控：怠速 ≥0.65，红线 ≤1.85', () {
      for (final core in ['idle', 'low', 'mid']) {
        final lo = corePlaySpeed(
            coreBand: core, rpm: 800, idleRpm: 800, redlineRpm: 6500);
        final hi = corePlaySpeed(
            coreBand: core, rpm: 6500, idleRpm: 800, redlineRpm: 6500);
        expect(lo, greaterThanOrEqualTo(0.65));
        expect(hi, lessThanOrEqualTo(1.86));
        // 怠速→红线至少升 70%，确保明显可闻。
        expect(hi / lo, greaterThan(1.7));
      }
    });

    test('核心段对应转速处倍速≈1.0', () {
      expect(
          corePlaySpeed(
              coreBand: 'idle', rpm: 800, idleRpm: 800, redlineRpm: 6500),
          closeTo(1.0, 1e-9));
      expect(
          corePlaySpeed(
              coreBand: 'low', rpm: 800 + 5700 * 0.25, idleRpm: 800,
              redlineRpm: 6500),
          closeTo(1.0, 1e-9));
      expect(
          corePlaySpeed(
              coreBand: 'mid', rpm: 800 + 5700 * 0.55, idleRpm: 800,
              redlineRpm: 6500),
          closeTo(1.0, 1e-9));
    });
  });

  group('冷启动包解析（v2.13.0 bug 修复回归）', () {
    final packs = [
      const EnginePackManifest(id: 'mazda6_na', name: '马自达6'),
      const EnginePackManifest(
          id: 'bmw_s58', name: '宝马 S58', turbo: true, hasBlowoff: true),
      const EnginePackManifest(
          id: 'synth', name: '电子', synthOnly: true, bands: []),
    ];

    test('已持久化 bmw_s58 → 解析到 bmw_s58（采样路径，而非退回 synth）', () {
      final p = resolveEnginePack('bmw_s58', packs);
      expect(p.id, 'bmw_s58');
      expect(p.synthOnly, false);
      // 采样路径条件：非 synthOnly。
      expect(!p.synthOnly, isTrue);
    });

    test('冷启动 manifest 为空（没先开设置页）→ 安全退回 synth，不抛错', () {
      final p = resolveEnginePack('bmw_s58', const []);
      expect(p.id, 'synth');
      expect(p.synthOnly, true);
    });

    test('packId 不在 manifest → 退回 synth，不抛 StateError', () {
      final p = resolveEnginePack('not_exists_xxx', packs);
      expect(p.id, 'synth');
    });

    test('分组归类正确', () {
      expect(enginePackGroup(const EnginePackManifest(id: 'ls_v8', name: '')),
          EnginePackGroup.na);
      expect(
          enginePackGroup(const EnginePackManifest(
              id: 'bmw_s58', name: '', turbo: true)),
          EnginePackGroup.turbo);
      expect(
          enginePackGroup(const EnginePackManifest(
              id: 'hellcat', name: '', supercharged: true)),
          EnginePackGroup.supercharged);
      expect(
          enginePackGroup(
              const EnginePackManifest(id: 'mazda_rotary', name: '')),
          EnginePackGroup.rotary);
      expect(
          enginePackGroup(
              const EnginePackManifest(id: 'synth', name: '', synthOnly: true)),
          EnginePackGroup.synth);
    });
  });
}
