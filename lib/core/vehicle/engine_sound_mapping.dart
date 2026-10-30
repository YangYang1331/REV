/// 引擎声浪「rpm → 发声参数」映射与生命周期状态机。
///
/// 纯 Dart、不依赖任何音频插件，全部参数在此算好后由平台层
/// （`EngineSoundService`）按约 50ms 节奏下发，杜绝拉链音/爆音。
///
/// 设计依据（v2.10.0 评审通过的方案）：
///  - 基频 f0 = 40 * pow(rpm/800, 1.2)：怠速 800rpm≈40Hz 低沉轰鸣；
///  - 叠加 0.5x（次八度，低转加重）/1x/2x/3x/4x 谐波，高转抬升 2x/3x 做力度；
///  - 一路噪声经低通，截止频率随 rpm 升高模拟排气；
///  - rpm 快速下降（松油收油）时短暂压增益再回弹；
///  - 怠速（rpm≈idle、车停着但没熄火）也要有持续低沉轰鸣，全程连续不中断。
library;

import 'dart:math' as math;
class EngineSoundParams {
  const EngineSoundParams({
    required this.fundamentalHz,
    required this.harmonicGains,
    required this.noiseLevel,
    required this.noiseCutoffHz,
    required this.masterGain,
    required this.rpmSmoothed,
    this.busCutoffHz = 16000,
    this.load = 0,
  });

  /// 基频（Hz）。平台层各谐波声部频率 = f0 × 阶次。
  final double fundamentalHz;

  /// 阶次（0.5 / 1 / 2 / 3 / 4）→ 增益（0..1）。
  final Map<double, double> harmonicGains;

  /// 排气噪声层增益（0..1，含电平分量）。
  final double noiseLevel;

  /// 噪声低通截止频率（Hz）：rpm 越高越亮，模拟高转排气气流。
  final double noiseCutoffHz;

  /// 总增益（0..1）：已含松油包络 duck；平台层再乘自己的淡入/duck 系数。
  final double masterGain;

  /// 平滑后的 rpm（平台层/调试用）。
  final double rpmSmoothed;

  /// 母线低通截止（Hz）：采样包与合成共用，随负荷/转速抬升音色亮度。
  final double busCutoffHz;

  /// 平滑后的负荷（0..1），仅作调试/显示。
  final double load;
}

class EngineSoundMapper {
  EngineSoundMapper({
    required this.idleRpm,
    required this.redlineRpm,
    this.baseFreqHz = 40.0,
    this.freqPower = 1.2,
    this.smoothTauMs = 50.0,
  }) {
    _smoothRpm = idleRpm.toDouble();
  }

  /// 怠速转速（来自车型档案，马6≈800）。
  final double idleRpm;

  /// 红线转速（马6≈6500）。
  final double redlineRpm;

  /// 怠速基频（Hz）。
  final double baseFreqHz;

  /// 频率指数：f0 = baseFreq * pow(rpm/idleRpm, power)。
  final double freqPower;

  /// rpm 指数平滑时间常数（ms）。
  final double smoothTauMs;

  late double _smoothRpm;
  double _coastDip = 0; // 松油压幅 0..1，回弹由平滑保证。

  /// 重置（进入/离开时调用）。
  void reset() {
    _smoothRpm = idleRpm;
    _coastDip = 0;
  }

  /// 喂入一帧 rpm，算出全部发声参数。[dtMs] 本帧距上帧毫秒数。
  ///
  /// 物理依据：排气脉冲基频 f = rpm/60 × (缸数/2)，音高只由转速决定；
  /// [load]（节气门/负荷 0..1）只改变脉冲强度与高频含量，
  /// [gear]（挡位，0=未知）只用于低速高挡的「闷音」判断。
  EngineSoundParams plan(double rpm, double dtMs,
      {double load = 0, int gear = 0}) {
    // 1) rpm 钳到 [idle*0.5, redline*1.05]，避免熄火跳变/过红区炸音。
    final clamped = rpm.clamp(idleRpm * 0.5, redlineRpm * 1.05);

    // 2) ~50ms 指数平滑，任何上游抖动都被吃掉。
    final dt = dtMs <= 0 ? smoothTauMs : dtMs;
    final alpha = dt / (smoothTauMs + dt);
    _smoothRpm += (clamped - _smoothRpm) * alpha;

    // 3) 归一化转带 0..1：idle→0，redline→1。
    var t = (_smoothRpm - idleRpm) / (redlineRpm - idleRpm);
    t = t.clamp(0.0, 1.0);

    // 4) 基频（评审公式）。
    final f0 = baseFreqHz *
        math.pow(_smoothRpm / idleRpm, freqPower).toDouble();

    // 5) 谐波增益：低转加重 0.5x 次八度轰鸣；高转抬 2x/3x/4x 出力度。
    double lerp(double a, double b) => a + (b - a) * t;
    final loadN = load.isFinite ? load.clamp(0.0, 1.0) : 0.0;
    // 低速高挡（拖挡）时排气脉冲间隔变长、声音发闷：抬低频、压高频。
    final lug = gear >= 4
        ? (1.0 - (_smoothRpm / (idleRpm * 1.9))).clamp(0.0, 1.0)
        : gear == 3
            ? (1.0 - (_smoothRpm / (idleRpm * 1.6))).clamp(0.0, 1.0) * 0.6
            : 0.0;
    final hiTilt = 0.80 + 0.45 * loadN - 0.25 * lug;
    final loTilt = 1.0 + 0.28 * lug - 0.06 * loadN;
    final harmonics = <double, double>{
      0.5: lerp(0.95, 0.30) * loTilt, // 次八度：怠速轰鸣主力，高转退
      1.0: lerp(0.55, 0.65) * loTilt,
      2.0: lerp(0.30, 0.90) * hiTilt,
      3.0: lerp(0.14, 0.85) * hiTilt,
      4.0: lerp(0.04, 0.45) * hiTilt,
    };

    // 6) 排气噪声：电平随 rpm 升高；低通截止 300Hz→3.8kHz。
    final noiseLevel = lerp(0.10, 0.42);
    final noiseCutoffHz = lerp(300.0, 3800.0);

    // 7) 松油包络：rpm 下滑快时压幅（压完靠平滑回弹，不另起锯齿）。
    //    速率估计：本帧 rpm 与上一帧平滑值之差 / dt（rpm/s）。
    final rate = (clamped - _smoothRpm) * 1000.0 / dt;
    var targetDip = 0.0;
    if (rate < -1500.0) {
      targetDip = ((-rate - 1500.0) / 3500.0).clamp(0.0, 0.55);
    }
    // dip 本身也平滑，快速下落时很快压下去、回弹缓慢。
    final dipAlpha = dt / (120.0 + dt); // 下压快、回放慢
    _coastDip += (targetDip - _coastDip) * dipAlpha;

    // 8) 总增益：基础响度 + 松油压幅；负荷越大脉冲越强（最多 +12%）。
    final master =
        lerp(0.55, 0.75) * (1.0 - _coastDip) * (0.94 + 0.14 * loadN);

    // 9) 母线低通：排气脉冲的高频含量随负荷与转速抬升。
    final busCutoff =
        (2400.0 + 5600.0 * loadN + 7000.0 * t - 1200.0 * lug).clamp(1800.0, 16000.0);

    return EngineSoundParams(
      fundamentalHz: f0,
      harmonicGains: harmonics,
      noiseLevel: noiseLevel,
      noiseCutoffHz: noiseCutoffHz,
      masterGain: master,
      rpmSmoothed: _smoothRpm,
      busCutoffHz: busCutoff,
      load: loadN,
    );
  }
}

/// 引擎声浪生命周期：发动机「活着（怠速/行驶）」vs「熄火/离车」。
///
/// 与 coast 状态机语义一致（rpm 长期≈idle×0.4 以下视为熄火），
/// 但独立、纯逻辑、可注入时钟，便于单测。
enum EngineSoundLife {
  /// 发动机在转（怠速或行驶）：声浪应播放。
  alive,

  /// 发动机已熄火（或长时间无帧）：声浪应停。
  off,
}

enum EngineLifeEvent {
  /// 无状态变化。
  none,

  /// 从熄火恢复到运转（重新上电/启动）。
  becameAlive,

  /// 从运转确认为熄火（rpm 长期≈0）。
  becameOff,
}

class EngineSoundLifeMachine {
  EngineSoundLifeMachine({
    required this.idleRpm,
    this.offRpmFactor = 0.4,
    this.offConfirmMs = 5000,
  });

  final double idleRpm;
  final double offRpmFactor;

  /// rpm 持续低于熄火阈值多久才确认真熄火。
  final int offConfirmMs;

  EngineSoundLife _state = EngineSoundLife.alive;
  int? _offSinceMs;

  EngineSoundLife get state => _state;

  double get _offRpm => idleRpm * offRpmFactor;

  /// 喂一帧 (rpm, nowMs)。速度不参与判定——只要 rpm 在怠速带以上就算活着。
  EngineLifeEvent update(double rpm, int nowMs) {
    final engineOff = rpm < _offRpm;

    if (!engineOff) {
      _offSinceMs = null;
      if (_state == EngineSoundLife.off) {
        _state = EngineSoundLife.alive;
        return EngineLifeEvent.becameAlive;
      }
      return EngineLifeEvent.none;
    }

    // rpm 接近 0：累计熄火时长。
    _offSinceMs ??= nowMs;
    if (_state == EngineSoundLife.alive &&
        nowMs - _offSinceMs! >= offConfirmMs) {
      _state = EngineSoundLife.off;
      _offSinceMs = null;
      return EngineLifeEvent.becameOff;
    }
    return EngineLifeEvent.none;
  }
}
