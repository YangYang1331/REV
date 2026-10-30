/// 加油记录与油耗计算（纯逻辑，便于单测）。
///
/// 长期油耗按"满箱到满箱"计算：上一箱加满的里程 → 本次加满的里程，
/// 期间所有加油量之和 / 行驶里程，这才是真实 L/100km；
/// 只加半箱的记录不参与分段，但仍计入总花费。
library;

class FuelRec {
  const FuelRec({
    required this.ts,
    required this.odo,
    required this.liters,
    required this.unitPrice,
    this.full = true,
    this.note = '',
    this.vehicleId = '',
  });

  /// 加油时间（毫秒时间戳）。
  final int ts;

  /// 所属车辆（多车车库 id；空串表示老数据，归当前车辆）。
  final String vehicleId;

  /// 加油时仪表里程（km）。
  final double odo;

  /// 本次加油量（L）。
  final double liters;

  /// 单价（元/L）。
  final double unitPrice;

  /// 是否加满（只有加满才能闭合一段油耗区间）。
  final bool full;

  final String note;

  double get cost => liters * unitPrice;

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'odo': odo,
        'l': liters,
        'p': unitPrice,
        if (!full) 'full': false,
        if (note.isNotEmpty) 'note': note,
        if (vehicleId.isNotEmpty) 'veh': vehicleId,
      };

  factory FuelRec.fromJson(Map<String, dynamic> j) => FuelRec(
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        odo: (j['odo'] as num?)?.toDouble() ?? 0,
        liters: (j['l'] as num?)?.toDouble() ?? 0,
        unitPrice: (j['p'] as num?)?.toDouble() ?? 0,
        full: j['full'] as bool? ?? true,
        note: j['note'] as String? ?? '',
        vehicleId: j['veh'] as String? ?? '',
      );
}

/// 一箱油区间（两次加满之间）。
class FuelSegment {
  const FuelSegment({
    required this.fromOdo,
    required this.toOdo,
    required this.liters,
    required this.cost,
    required this.toTs,
  });

  final double fromOdo;
  final double toOdo;
  final double liters;
  final double cost;
  final int toTs;

  double get km => toOdo - fromOdo;
  double? get l100 => km > 1 ? liters / km * 100 : null;
}

class FuelStats {
  const FuelStats({
    required this.segments,
    required this.totalLiters,
    required this.totalCost,
    required this.fills,
  });

  final List<FuelSegment> segments;
  final double totalLiters;
  final double totalCost;
  final int fills;

  static const FuelStats empty = FuelStats(
    segments: [],
    totalLiters: 0,
    totalCost: 0,
    fills: 0,
  );

  /// 从全部记录里算统计（内部先按里程排序，输入顺序无所谓）。
  static FuelStats of(List<FuelRec> recs) {
    if (recs.isEmpty) return empty;
    final sorted = List<FuelRec>.from(recs)
      ..sort((a, b) => a.odo.compareTo(b.odo));
    final segs = <FuelSegment>[];
    FuelRec? lastFull;
    var pendingLiters = 0.0;
    var pendingCost = 0.0;
    for (final r in sorted) {
      if (lastFull == null) {
        if (r.full) {
          lastFull = r;
        } else {
          pendingLiters += r.liters;
          pendingCost += r.cost;
        }
        continue;
      }
      pendingLiters += r.liters;
      pendingCost += r.cost;
      if (r.full) {
        if (r.odo - lastFull.odo > 1) {
          segs.add(FuelSegment(
            fromOdo: lastFull.odo,
            toOdo: r.odo,
            liters: pendingLiters,
            cost: pendingCost,
            toTs: r.ts,
          ));
        }
        lastFull = r;
        pendingLiters = 0;
        pendingCost = 0;
      }
    }
    return FuelStats(
      segments: segs,
      totalLiters: sorted.fold(0.0, (a, r) => a + r.liters),
      totalCost: sorted.fold(0.0, (a, r) => a + r.cost),
      fills: sorted.length,
    );
  }

  /// 长期平均油耗（L/100km）；没有任何完整区间时为 null。
  double? get avgL100 {
    final km = segments.fold(0.0, (a, s) => a + s.km);
    final l = segments.fold(0.0, (a, s) => a + s.liters);
    return km > 1 ? l / km * 100 : null;
  }

  /// 最近一段（最后一箱）油耗。
  double? get lastL100 =>
      segments.isEmpty ? null : segments.last.l100;

  /// 每公里油费（元/km），按区间油费 / 区间里程。
  double? get costPerKm {
    final km = segments.fold(0.0, (a, s) => a + s.km);
    final cost = segments.fold(0.0, (a, s) => a + s.cost);
    return km > 1 ? cost / km : null;
  }

  /// 最近 N 段的平均油耗（趋势对比用）。
  double? recentL100([int n = 3]) {
    if (segments.isEmpty) return null;
    final tail = segments.length <= n
        ? segments
        : segments.sublist(segments.length - n);
    final km = tail.fold(0.0, (a, s) => a + s.km);
    final l = tail.fold(0.0, (a, s) => a + s.liters);
    return km > 1 ? l / km * 100 : null;
  }

  /// 趋势：最近 3 段 vs 更早，正值表示最近更费油（L/100 差）。
  double? get trendL100 {
    if (segments.length < 4) return null;
    final recent = recentL100(3);
    final older = () {
      final head = segments.sublist(0, segments.length - 3);
      final km = head.fold(0.0, (a, s) => a + s.km);
      final l = head.fold(0.0, (a, s) => a + s.liters);
      return km > 1 ? l / km * 100 : null;
    }();
    if (recent == null || older == null) return null;
    return recent - older;
  }
}

/// 到期提醒（保险 / 年检这类纯日期项）。
class DueInfo {
  const DueInfo(this.label, this.date);

  final String label;
  final DateTime date;

  int get daysLeft => date.difference(DateTime.now()).inDays;

  bool get overdue => daysLeft < 0;
  bool get soon => !overdue && daysLeft <= 30;
}
