import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/vehicle/engine_profile.dart';
import 'package:obd_dashboard/core/vehicle/engine_sound_mapping.dart';

void main() {
  group('EngineSoundMapper 基频公式', () {
    test('点火频率：怠速 800rpm（I4）≈26.7Hz；红线远高于怠速', () {
      final m = EngineSoundMapper(idleRpm: 800, redlineRpm: 6500);
      // 预热到稳定（平滑收敛）。
      for (var i = 0; i < 60; i++) {
        m.plan(800, 50);
      }
      final idle = m.plan(800, 50);
      // 四冲程四缸：800/60 × 2 = 26.67Hz（每转点火 2 次）。
      expect(idle.fundamentalHz, closeTo(26.7, 1.0));

      m.reset();
      for (var i = 0; i < 120; i++) {
        m.plan(6500, 50);
      }
      final red = m.plan(6500, 50);
      expect(red.fundamentalHz, closeTo(216.7, 3.0));
      expect(red.fundamentalHz, greaterThan(idle.fundamentalHz * 2.5));
    });

    test('不同引擎档案：点火频率随每转点火次数线性升高', () {
      EngineSoundParams stable(EngineProfile p, double rpm) {
        final m = EngineSoundMapper(
            idleRpm: 800, redlineRpm: 8000, profile: p);
        for (var i = 0; i < 120; i++) {
          m.plan(rpm, 50);
        }
        return m.plan(rpm, 50);
      }

      // 800rpm：I4(2/转)=26.7、V8(4/转)=53.3、V12(6/转)=80、转子(6/转)=80。
      expect(stable(EngineProfile.i4, 800).fundamentalHz, closeTo(26.7, 1.0));
      expect(stable(EngineProfile.v8, 800).fundamentalHz, closeTo(53.3, 1.5));
      expect(stable(EngineProfile.v12, 800).fundamentalHz, closeTo(80.0, 2.0));
      expect(
          stable(EngineProfile.rotary, 800).fundamentalHz, closeTo(80.0, 2.0));
    });

    test('rpm 被钳位：0 或超红区都不会炸参数', () {
      final m = EngineSoundMapper(idleRpm: 800, redlineRpm: 6500);
      final low = m.plan(0, 50);
      final high = m.plan(12000, 50);
      expect(low.fundamentalHz.isFinite, true);
      expect(high.fundamentalHz.isFinite, true);
      expect(high.fundamentalHz, lessThan(5000));
    });
  });

  group('谐波与噪声塑形', () {
    test('低转加重次八度(0.5x)，高转抬升 3x', () {
      final m = EngineSoundMapper(idleRpm: 800, redlineRpm: 6500);
      for (var i = 0; i < 80; i++) {
        m.plan(800, 50);
      }
      final idle = m.plan(800, 50);
      m.reset();
      for (var i = 0; i < 160; i++) {
        m.plan(5000, 50);
      }
      final high = m.plan(5000, 50);
      // 次八度低转重
      expect(idle.harmonicGains[0.5]!, greaterThan(high.harmonicGains[0.5]!));
      // 3x 高转重
      expect(high.harmonicGains[3.0]!, greaterThan(idle.harmonicGains[3.0]!));
    });

    test('噪声低通截止随 rpm 升高', () {
      final m = EngineSoundMapper(idleRpm: 800, redlineRpm: 6500);
      for (var i = 0; i < 80; i++) {
        m.plan(800, 50);
      }
      final idle = m.plan(800, 50);
      m.reset();
      for (var i = 0; i < 160; i++) {
        m.plan(6500, 50);
      }
      final red = m.plan(6500, 50);
      expect(red.noiseCutoffHz, greaterThan(idle.noiseCutoffHz * 3));
      expect(red.noiseLevel, greaterThan(idle.noiseLevel));
    });
  });

  group('平滑与松油包络', () {
    test('rpm 跳变不会瞬间传导（50ms 指数平滑）', () {
      final m = EngineSoundMapper(idleRpm: 800, redlineRpm: 6500);
      for (var i = 0; i < 80; i++) {
        m.plan(800, 50);
      }
      final f0Idle = m.plan(800, 50).fundamentalHz;
      final jump = m.plan(6500, 50); // 只过一帧
      // 红线瞬时频率约 490Hz；一帧平滑后明显低于它（未直接跳变）。
      expect(jump.fundamentalHz, greaterThan(f0Idle));
      expect(jump.fundamentalHz, lessThan(400));
    });

    test('快速松油（rpm 陡降）总增益被压低', () {
      final m = EngineSoundMapper(idleRpm: 800, redlineRpm: 6500);
      // 先拉到 4500 稳定
      for (var i = 0; i < 120; i++) {
        m.plan(4500, 50);
      }
      final cruise = m.plan(4500, 50).masterGain;
      // 50ms 内 4500→1000：rate = -70000 rpm/s，远超 -1500 阈值
      final decel = m.plan(1000, 50);
      expect(decel.masterGain, lessThan(cruise * 0.9));
    });
  });

  group('EngineSoundLifeMachine 熄火判定', () {
    test('rpm≈idle 车停着：保持 alive（红灯停车不熄火）', () {
      final life = EngineSoundLifeMachine(idleRpm: 800, offConfirmMs: 5000);
      var ev = EngineLifeEvent.none;
      for (var t = 0; t < 15000; t += 500) {
        ev = life.update(800, t);
      }
      expect(life.state, EngineSoundLife.alive);
      expect(ev, EngineLifeEvent.none);
    });

    test('rpm≈0 持续 5s → becameOff；恢复转速 → becameAlive', () {
      final life = EngineSoundLifeMachine(idleRpm: 800, offConfirmMs: 5000);
      var ev = EngineLifeEvent.none;
      for (var t = 0; t < 4000; t += 500) {
        ev = life.update(0, t);
      }
      expect(life.state, EngineSoundLife.alive); // 未满 5s
      ev = life.update(0, 6000);
      expect(ev, EngineLifeEvent.becameOff);
      expect(life.state, EngineSoundLife.off);

      ev = life.update(900, 6500);
      expect(ev, EngineLifeEvent.becameAlive);
      expect(life.state, EngineSoundLife.alive);
    });
  });
}
