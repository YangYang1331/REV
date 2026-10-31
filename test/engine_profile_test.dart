import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/vehicle/engine_profile.dart';
import 'package:obd_dashboard/core/vehicle/engine_sound_mapping.dart';

void main() {
  group('EngineProfile 点火频率', () {
    test('四冲程 f = rpm/60 × 每转点火次数', () {
      expect(EngineProfile.i4.firingHz(800), closeTo(26.67, 0.05));
      expect(EngineProfile.i6.firingHz(6000), closeTo(300.0, 0.01));
      expect(EngineProfile.v8.firingHz(6000), closeTo(400.0, 0.01));
      expect(EngineProfile.v10.firingHz(6000), closeTo(500.0, 0.01));
      expect(EngineProfile.v12.firingHz(8000), closeTo(800.0, 0.01));
      expect(EngineProfile.rotary.firingHz(9000), closeTo(900.0, 0.01));
    });

    test('非法 rpm 返回 0，不抛异常', () {
      expect(EngineProfile.i4.firingHz(0), 0);
      expect(EngineProfile.i4.firingHz(-100), 0);
      expect(EngineProfile.i4.firingHz(double.nan), 0);
    });

    test('每个档案都覆盖全部阶次权重', () {
      for (final p in EngineProfile.all) {
        for (final o in kEngineOrders) {
          expect(p.idleWeights.containsKey(o), true, reason: '${p.id} idle $o');
          expect(p.highWeights.containsKey(o), true, reason: '${p.id} high $o');
        }
      }
    });

    test('byId 找不到时回退 I4', () {
      expect(EngineProfile.byId('v8').id, 'v8');
      expect(EngineProfile.byId('nope').id, 'i4');
    });

    test('采样包 → 档案映射', () {
      expect(EngineProfile.forPack('bmw_s58').id, 'i6');
      expect(EngineProfile.forPack('mustang_gt').id, 'v8');
      expect(EngineProfile.forPack('lambo_v10').id, 'v10');
      expect(EngineProfile.forPack('v12').id, 'v12');
      expect(EngineProfile.forPack('subaru_sti').id, 'h4');
      expect(EngineProfile.forPack('porsche_gt3').id, 'h6');
      expect(EngineProfile.forPack('mazda_rotary').id, 'rotary');
      expect(EngineProfile.forPack('mazda6_na').id, 'i4');
    });
  });

  group('EngineTuning 调音', () {
    test('越界值被钳位', () {
      const t = EngineTuning();
      final hi = t.copyWith(brightness: 9, lowEnd: 9, grit: 9, popAmount: 9);
      expect(hi.brightness, 1.6);
      expect(hi.lowEnd, 1.6);
      expect(hi.grit, 1.0);
      expect(hi.popAmount, 1.0);
      final lo = t.copyWith(brightness: -5, lowEnd: -5, grit: -5, popAmount: -5);
      expect(lo.brightness, 0.6);
      expect(lo.lowEnd, 0.5);
      expect(lo.grit, 0.0);
      expect(lo.popAmount, 0.0);
    });

    test('亮度只抬 2 阶以上，低频只抬 1 阶以下', () {
      const t = EngineTuning(brightness: 1.4, lowEnd: 1.4);
      expect(t.highOrderScale(0.5), 1.0);
      expect(t.highOrderScale(1.0), 1.0);
      expect(t.highOrderScale(8.0), greaterThan(t.highOrderScale(2.0)));
      expect(t.highOrderScale(2.0), greaterThan(1.0));
      expect(t.lowOrderScale(0.5), 1.4);
      expect(t.lowOrderScale(1.0), 1.4);
      expect(t.lowOrderScale(2.0), 1.0);
    });

    test('JSON 往返', () {
      const t = EngineTuning(brightness: 1.2, lowEnd: 0.8, grit: 0.6, popAmount: 0.3);
      final back = EngineTuning.fromJson(t.toJson());
      expect(back.brightness, closeTo(1.2, 1e-9));
      expect(back.lowEnd, closeTo(0.8, 1e-9));
      expect(back.grit, closeTo(0.6, 1e-9));
      expect(back.popAmount, closeTo(0.3, 1e-9));
    });
  });

  group('档案 + 调音 → 发声参数', () {
    EngineSoundParams stable(EngineProfile p, double rpm,
        {EngineTuning tuning = const EngineTuning()}) {
      final m = EngineSoundMapper(
          idleRpm: 800, redlineRpm: 8000, profile: p, tuning: tuning);
      for (var i = 0; i < 160; i++) {
        m.plan(rpm, 50);
      }
      return m.plan(rpm, 50);
    }

    test('V8 半阶（怠速咕噜）比 I4 重', () {
      final i4 = stable(EngineProfile.i4, 800);
      final v8 = stable(EngineProfile.v8, 800);
      expect(v8.harmonicGains[0.5]!, greaterThan(i4.harmonicGains[0.5]!));
    });

    test('V10 高转高阶（6x/8x）比 V12 更亮', () {
      final v10 = stable(EngineProfile.v10, 7000);
      final v12 = stable(EngineProfile.v12, 7000);
      expect(v10.harmonicGains[8.0]!, greaterThan(v12.harmonicGains[8.0]!));
    });

    test('调亮度会抬高高阶增益，不改基频', () {
      final base = stable(EngineProfile.i4, 4000);
      final bright = stable(EngineProfile.i4, 4000,
          tuning: const EngineTuning(brightness: 1.5));
      expect(bright.harmonicGains[8.0]!, greaterThan(base.harmonicGains[8.0]!));
      expect(bright.fundamentalHz, closeTo(base.fundamentalHz, 1e-9));
    });

    test('低频厚度只抬 1 阶以下', () {
      final base = stable(EngineProfile.v8, 2000);
      final thick = stable(EngineProfile.v8, 2000,
          tuning: const EngineTuning(lowEnd: 1.5));
      expect(thick.harmonicGains[1.0]!, greaterThan(base.harmonicGains[1.0]!));
      expect(thick.harmonicGains[6.0]!, closeTo(base.harmonicGains[6.0]!, 1e-9));
    });

    test('踩油瞬态抬总增益，颗粒量随调音变化', () {
      final m = EngineSoundMapper(idleRpm: 800, redlineRpm: 8000);
      for (var i = 0; i < 40; i++) {
        m.plan(3000, 50, load: 0.1);
      }
      final cruise = m.plan(3000, 50, load: 0.1);
      final tip = m.plan(3000, 50, load: 0.9);
      expect(tip.masterGain, greaterThan(cruise.masterGain));

      final soft = EngineSoundMapper(
          idleRpm: 800,
          redlineRpm: 8000,
          tuning: const EngineTuning(grit: 0.0));
      final hard = EngineSoundMapper(
          idleRpm: 800,
          redlineRpm: 8000,
          tuning: const EngineTuning(grit: 1.0));
      expect(soft.plan(3000, 50).grit, 0);
      expect(hard.plan(3000, 50).grit, greaterThan(0.2));
    });
  });
}
