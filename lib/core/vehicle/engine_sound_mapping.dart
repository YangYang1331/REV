/// 引擎声浪「rpm → 发声参数」映射与生命周期状态机。
///
/// 纯 Dart、不依赖任何音频插件，全部参数在此算好后由平台层
/// （`EngineSoundService`）按约 50ms 节奏下发，杜绝拉链音/爆音。
///
/// v2.17.6 起基频改为物理点火频率（借鉴内燃机声浪原理）：
///  - 四冲程 f_fire = rpm/60 × (缸数/2)，转速升高 → 点火更密 → 音调线性升高；
///  - 谐波取 [kEngineOrders]（0.5x 半阶 … 8x），怠速/高转两套权重按
///    引擎档案（[EngineProfile]）插值，V8 半阶重、V10 高阶亮、转子持续啸叫；
///  - 用户调音（[EngineTuning]）在权重上再叠亮度 / 低频厚度；
///  - 一路噪声经低通，截止频率随 rpm 与负荷升高模拟排气气流；
///  - 松油（rpm 快速下降）压增益形成回弹包络，配合回火放炮；
///  - 怠速（rpm≈idle、车停着但没熄火）也要有持续低沉轰鸣，全程连续不中断。
library;

import 'package:obd_dashboard/core/vehicle/engine_profile.dart';

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
    this.grit = 0,
    this.engineId = 'i4',
  });

  /// 基频（Hz）= 点火频率。平台层各谐波声部频率 = f0 × 阶次。
  final double fundamentalHz;

  /// 阶次（0.5 / 1 / 2 / 3 / 4 / 6 / 8）→ 增益（0..1）。
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

  /// 颗粒/失真量（0..1）= 用户 grit × 引擎粗糙度，平台层据此驱动波形整形。
  final double grit;

  /// 当前引擎档案 id（调试/UI 显示）。
  final String engineId;
}

class EngineSoundMapper {
  EngineSoundMapper({
    required this.idleRpm,
    required this.redlineRpm,
    EngineProfile? profile,
    EngineTuning tuning = const EngineTuning(),
    this.smoothTauMs = 50.0,
  })  : profile = profile ?? EngineProfile.i4,
        _tuning = tuning {
    _smoothRpm = idleRpm.toDouble();
  }

  /// 怠速转速（来自车型档案，马6≈800）。
  final double idleRpm;

  /// 红线转速（马6≈6500）。
  final double redlineRpm;

  /// 引擎档案（缸数/点火次数/谐波性格）。
  EngineProfile profile;

  /// rpm 指数平滑时间常数（ms）。
  final double smoothTauMs;

  EngineTuning _tuning;
  EngineTuning get tuning => _tuning;

  late double _smoothRpm;
  double _coastDip = 0; // 松油压幅 0..1，回弹由平滑保证。
  double _prevLoad = 0;
  double _tipIn = 0; // 油门变化率带来的瞬态冲击 0..1

  void setProfile(EngineProfile p) {
    profile = p;
  }

  void setTuning(EngineTuning t) {
    _tuning = t;
  }

  /// 重置（进入/离开时调用）。
  void reset() {
    _smoothRpm = idleRpm;
    _coastDip = 0;
    _prevLoad = 0;
    _tipIn = 0;
  }

  /// 喂入一帧 rpm，算出全部发声参数。[dtMs] 本帧距上帧毫秒数。
  ///
  /// 物理依据：点火频率 f = rpm/60 × 每转点火次数，音高只由转速决定；
  /// [load]（节气门/负荷 0..1）改变脉冲强度与高频含量、并带来踩油瞬态，
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
    final span = (redlineRpm - idleRpm).abs();
    var t = span <= 0 ? 0.0 : (_smoothRpm - idleRpm) / span;
    t = t.clamp(0.0, 1.0);

    // 4) 基频 = 点火频率（物理），非法值兜底。
    var f0 = profile.firingHz(_smoothRpm);
    if (!f0.isFinite || f0 <= 0) f0 = profile.firingHz(idleRpm);

    // 5) 负荷瞬态：猛踩油门（load 快速上升）给一瞬间的冲击与高频。
    final loadN = load.isFinite ? load.clamp(0.0, 1.0) : 0.0;
    final dLoad = (loadN - _prevLoad).clamp(-1.0, 1.0);
    _prevLoad = loadN;
    final tipTarget = dLoad > 0 ? (dLoad * 6.0).clamp(0.0, 1.0) : 0.0;
    _tipIn += (tipTarget - _tipIn) * (tipTarget > _tipIn ? 0.35 : 0.10);

    // 6) 谐波：档案怠速/高转两套权重插值 + 调音 + 负荷/拖挡塑形。
    double lug;
    if (gear >= 4) {
      lug = (1.0 - (_smoothRpm / (idleRpm * 1.9))).clamp(0.0, 1.0);
    } else if (gear == 3) {
      lug = (1.0 - (_smoothRpm / (idleRpm * 1.6))).clamp(0.0, 1.0) * 0.6;
    } else {
      lug = 0.0;
    }
    final hiTilt = 0.82 + 0.40 * loadN + 0.22 * _tipIn - 0.25 * lug;
    final loTilt = 1.0 + 0.26 * lug - 0.05 * loadN;

    // 电子阀门排气（领克 03+ 等）：约 3000rpm 开阀。开阀前高阶泛音被
    // 消音器压住、总电平也低一档；开阀后一起放出来。过渡带 ±350rpm，
    // 用 smoothstep 避免开关瞬间的台阶（会听成「咔」一下）。
    final vOpen = profile.valveOpenRpm;
    var valve = 1.0;
    if (vOpen > 0) {
      final raw = ((_smoothRpm - (vOpen - 350.0)) / 700.0).clamp(0.0, 1.0);
      valve = raw * raw * (3.0 - 2.0 * raw);
    }

    final harmonics = <double, double>{};
    for (final order in kEngineOrders) {
      final idleW = profile.idleWeights[order] ?? 0.0;
      final highW = profile.highWeights[order] ?? 0.0;
      var g = idleW + (highW - idleW) * t;
      g *= order < 2.0 ? loTilt : hiTilt;
      g *= _tuning.lowOrderScale(order) * _tuning.highOrderScale(order);
      if (vOpen > 0 && order >= 3.0) g *= 0.55 + 0.45 * valve;
      harmonics[order] = g.clamp(0.0, 1.2);
    }

    // 7) 排气噪声：电平随 rpm 升高；低通截止 300Hz→3.8kHz。
    final noiseLevel = (profile.noiseIdle +
            (profile.noiseHigh - profile.noiseIdle) * t) *
        (0.9 + 0.2 * loadN);
    final noiseCutoffHz = 300.0 + 3500.0 * t;

    // 8) 松油包络：rpm 下滑快时压幅（压完靠平滑回弹，不另起锯齿）。
    final rate = (clamped - _smoothRpm) * 1000.0 / dt;
    var targetDip = 0.0;
    if (rate < -1500.0) {
      targetDip = ((-rate - 1500.0) / 3500.0).clamp(0.0, 0.55);
    }
    final dipAlpha = dt / (120.0 + dt); // 下压快、回放慢
    _coastDip += (targetDip - _coastDip) * dipAlpha;

    // 9) 总增益：基础响度 + 松油压幅；负荷越大脉冲越强（+12%），
    //    踩油瞬态再抬 8% 做 attack。
    final master = (0.55 + 0.20 * t) *
        (1.0 - _coastDip) *
        (0.94 + 0.14 * loadN) *
        (1.0 + 0.08 * _tipIn) *
        (0.86 + 0.14 * valve);

    // 10) 母线低通：排气脉冲的高频含量随负荷与转速抬升。
    final busCutoff =
        (2400.0 + 5600.0 * loadN + 7000.0 * t - 1200.0 * lug)
            .clamp(1800.0, 16000.0);

    return EngineSoundParams(
      fundamentalHz: f0,
      harmonicGains: harmonics,
      noiseLevel: noiseLevel.clamp(0.0, 0.8),
      noiseCutoffHz: noiseCutoffHz,
      masterGain: master.clamp(0.0, 1.0),
      rpmSmoothed: _smoothRpm,
      busCutoffHz: busCutoff,
      load: loadN,
      grit: (_tuning.grit * profile.roughness).clamp(0.0, 1.0),
      engineId: profile.id,
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
