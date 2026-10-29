/// 自定义 Trigger → Action 规则引擎（纯逻辑、可单测）。
///
/// 规则形如：当某个量（水温/转速/电压/车速）越过阈值时触发动作
/// （红屏 flash / 换挡灯 / 播报）。带滞回（hysteresis）防抖，避免阈值附近抖动反复触发。
library;

/// 被监测的量。
enum TriggerMetric { coolant, rpm, voltage, speed, oilTemp }

/// 比较方向。
enum TriggerOp { above, below }

/// 触发后要做的动作。
class TriggerAction {
  const TriggerAction({
    this.redScreen = false,
    this.shiftLamp = false,
    this.announce = false,
  });

  final bool redScreen;
  final bool shiftLamp;

  /// 需要 TTS 播报（由 TtsService 在规则触发边沿朗读，见 lab_screen）。
  final bool announce;

  TriggerAction merge(TriggerAction o) => TriggerAction(
        redScreen: redScreen || o.redScreen,
        shiftLamp: shiftLamp || o.shiftLamp,
        announce: announce || o.announce,
      );
}

/// 一条规则。
class TriggerRule {
  const TriggerRule({
    required this.id,
    required this.metric,
    required this.op,
    required this.threshold,
    required this.action,
    this.hysteresis = 2.0,
  });

  final String id;
  final TriggerMetric metric;
  final TriggerOp op;
  final double threshold;

  /// 触发后需回落多少（同度量单位）才解除，防抖。
  final double hysteresis;
  final TriggerAction action;
}

/// 单条规则的状态机（滞回）。
class _RuleState {
  bool fired = false;
}

/// 一帧输入快照（取需要的量）。
class TriggerSample {
  const TriggerSample({
    this.coolant,
    this.rpm,
    this.voltage,
    this.speed,
    this.oilTemp,
  });

  final double? coolant;
  final double? rpm;
  final double? voltage;
  final double? speed;
  final double? oilTemp;

  double? valueOf(TriggerMetric m) {
    switch (m) {
      case TriggerMetric.coolant:
        return coolant;
      case TriggerMetric.rpm:
        return rpm;
      case TriggerMetric.voltage:
        return voltage;
      case TriggerMetric.speed:
        return speed;
      case TriggerMetric.oilTemp:
        return oilTemp;
    }
  }
}

/// 规则引擎：喂采样，返回本帧新触发/解除的动作事件。
class TriggerEngine {
  TriggerEngine({List<TriggerRule>? rules})
      : _rules = List.of(rules ?? const []);

  final List<TriggerRule> _rules;
  final Map<String, _RuleState> _states = {};

  List<TriggerRule> get rules => List.unmodifiable(_rules);

  void setRules(List<TriggerRule> rules) {
    _rules
      ..clear()
      ..addAll(rules);
  }

  /// 评估一帧。返回本帧"新进入触发态"的动作（合并）与"仍在触发"的量。
  /// 只在阈值穿越边沿产出事件，不重复刷屏。
  TriggerOutcome update(TriggerSample s) {
    final firedNow = <TriggerAction>[];
    final active = <String>{};
    for (final r in _rules) {
      final v = s.valueOf(r.metric);
      if (v == null) continue;
      final st = _states.putIfAbsent(r.id, () => _RuleState());
      final shouldFire = r.op == TriggerOp.above
          ? v >= r.threshold
          : v <= r.threshold;

      if (!st.fired && shouldFire) {
        st.fired = true;
        firedNow.add(r.action);
      } else if (st.fired) {
        // 滞回：above 规则需回落到 threshold - hysteresis 才解除。
        final released = r.op == TriggerOp.above
            ? v <= (r.threshold - r.hysteresis)
            : v >= (r.threshold + r.hysteresis);
        if (released) st.fired = false;
      }
      if (st.fired) active.add(r.id);
    }
    TriggerAction merged = const TriggerAction();
    for (final a in firedNow) {
      merged = merged.merge(a);
    }
    return TriggerOutcome(justFired: merged, activeIds: active);
  }
}

class TriggerOutcome {
  const TriggerOutcome({required this.justFired, required this.activeIds});
  final TriggerAction justFired;
  final Set<String> activeIds;

  bool get hasFired =>
      justFired.redScreen || justFired.shiftLamp || justFired.announce;
}
