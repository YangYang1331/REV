/// 蓝牙/USB 手柄换挡按键映射（纯逻辑、可单测）。
///
/// 键位符号沿用原 REV AOT 快照里出现的 GameButton1–16 / A–Z 命名：
/// 每个物理键有一个稳定符号 id（如 "GameButton1"、"A"、"DPadUp"）。
/// 默认把常见拨片位置映射到升挡/降挡，用户可在设置里点按重映射。
library;

/// 一个按键可承担的换挡动作。
enum ShiftAction { none, up, down }

/// 按键映射表：符号 id → 动作。默认值见 [GearShiftMap.defaults]。
class GearShiftMap {
  const GearShiftMap({required this.assignments});

  /// symbolId → 动作。
  final Map<String, ShiftAction> assignments;

  /// 默认映射：右拨片/X/A 升挡，左拨片/B/X 降挡（可改）。
  static Map<String, ShiftAction> get defaults => const {
        'GameButton5': ShiftAction.up, // 右拨片（常见）
        'GameButton4': ShiftAction.down, // 左拨片
        'R1': ShiftAction.up,
        'L1': ShiftAction.down,
      };

  factory GearShiftMap.initial() =>
      GearShiftMap(assignments: Map.of(defaults));

  /// 该键的动作（未映射为 none）。
  ShiftAction actionFor(String symbol) =>
      assignments[symbol] ?? ShiftAction.none;

  /// 计算按键按下后档位变化：up +1，down -1，none 0。
  /// [current] 当前档（0=空挡，-1=倒挡），[maxGear] 上限保护。
  /// 返回新档位（夹在 -1..maxGear）。
  int applyPress(String symbol, int current, {int maxGear = 8}) {
    final a = actionFor(symbol);
    int next = current;
    switch (a) {
      case ShiftAction.up:
        next = current + 1;
        if (next > maxGear) next = maxGear;
        break;
      case ShiftAction.down:
        next = current - 1;
        if (next < -1) next = -1;
        break;
      case ShiftAction.none:
        break;
    }
    return next;
  }

  /// 重绑某个键（同动作切换）。返回新实例。
  GearShiftMap rebind(String symbol, ShiftAction action) {
    final m = Map<String, ShiftAction>.from(assignments);
    if (action == ShiftAction.none) {
      m.remove(symbol);
    } else {
      // 同一动作只允许一个键：先清掉已有同动作键，避免双键竞争。
      m.removeWhere((k, v) => v == action);
      m[symbol] = action;
    }
    return GearShiftMap(assignments: m);
  }

  Map<String, dynamic> toJson() =>
      assignments.map((k, v) => MapEntry(k, v.name));

  factory GearShiftMap.fromJson(Map<String, dynamic> j) {
    final m = <String, ShiftAction>{};
    j.forEach((k, v) {
      final a = ShiftAction.values.where((e) => e.name == v).firstOrNull();
      if (a != null && a != ShiftAction.none) m[k] = a;
    });
    // 已存映射即权威（用户重绑/解绑要保留）；无存档时由调用方用 initial()。
    return GearShiftMap(assignments: m);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? firstOrNull() => isEmpty ? null : first;
}
