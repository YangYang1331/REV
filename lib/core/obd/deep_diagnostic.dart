/// 深度诊断纯逻辑（冻结帧 / 待定码 / 永久码 / 排放就绪）。
///
/// 与 IO 分离，便于单测：输入是 ELM327 的原始应答文本，输出是结构体。
library;

/// 单个排放监测项。
class ReadinessMonitor {
  const ReadinessMonitor({
    required this.name,
    required this.supported,
    required this.complete,
  });

  final String name;
  final bool supported;
  final bool complete;
}

/// PID 01 01 的解析结果。
class ReadinessReport {
  const ReadinessReport({
    required this.milOn,
    required this.dtcCount,
    required this.monitors,
  });

  /// 故障灯（MIL）是否点亮。
  final bool milOn;

  /// ECU 报告的当前故障码数量（A 字节低 7 位）。
  final int dtcCount;

  final List<ReadinessMonitor> monitors;

  /// 支持且未完成的项（年检/送检前需要跑完）。
  List<ReadinessMonitor> get incomplete =>
      monitors.where((m) => m.supported && !m.complete).toList();

  bool get ready => incomplete.isEmpty;
}

/// 冻结帧里的一个数据项。
class FreezeFrameField {
  const FreezeFrameField(this.label, this.value, this.unit);

  final String label;
  final double value;
  final String unit;

  String get display {
    final v = unit == 'rpm' || unit == 'km' || unit == 's'
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$v $unit';
  }
}

/// 冻结帧：触发故障码那一刻的工况快照。
class FreezeFrame {
  const FreezeFrame({this.dtc, this.fields = const []});

  final String? dtc;
  final List<FreezeFrameField> fields;

  bool get isEmpty => dtc == null && fields.isEmpty;
}

/// 深度诊断解析器。
class DeepDiagnosticCodec {
  const DeepDiagnosticCodec._();

  /// 取出 marker 之后的数据字节（十六进制串）。
  static String? payloadAfter(String raw, String marker) {
    final s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    final i = s.indexOf(marker);
    if (i < 0) return null;
    return s.substring(i + marker.length);
  }

  /// Mode 03 / 07 / 0A 通用解析。
  ///
  /// [marker] 为正响应前两位：43 / 47 / 4A。
  /// 结构与 Mode 03 一致：`<marker> <count> <DTC×n>`，count 可选。
  static List<String> parseCodes(String raw, String marker) {
    final body = payloadAfter(raw, marker);
    if (body == null) return const [];
    var s = body;
    final out = <String>[];
    if (s.length >= 2) {
      final count = int.tryParse(s.substring(0, 2), radix: 16) ?? 0;
      final withCount = _decodePairs(s.substring(2), count);
      if (count == 0 || withCount.isNotEmpty) return withCount;
    }
    out.addAll(_decodePairs(s, null));
    return out;
  }

  static List<String> _decodePairs(String hex, int? expected) {
    final out = <String>[];
    var pos = 0;
    while (pos + 4 <= hex.length) {
      final b0 = int.tryParse(hex.substring(pos, pos + 2), radix: 16);
      final b1 = int.tryParse(hex.substring(pos + 2, pos + 4), radix: 16);
      pos += 4;
      if (b0 == null || b1 == null) continue;
      if (b0 == 0 && b1 == 0) continue;
      out.add(encodeDtc(b0, b1));
      if (expected != null && out.length >= expected) break;
    }
    return out;
  }

  /// 两字节 → SAE J2012 五字符码（与 DtcCodec 同一规则）。
  static String encodeDtc(int b0, int b1) {
    const letters = ['P', 'C', 'B', 'U'];
    final family = (b0 >> 6) & 0x03;
    final high = (b0 >> 4) & 0x03;
    final d1 = (b0 & 0x0F).toRadixString(16).toUpperCase();
    final d2 = (b1 >> 4).toRadixString(16).toUpperCase();
    final d3 = (b1 & 0x0F).toRadixString(16).toUpperCase();
    return '${letters[family]}$high$d1$d2$d3';
  }

  /// 解析 PID 01 01（排放就绪状态），按 SAE J1979 位定义。
  ///
  /// 应答 41 01 A B C D：
  ///  A: bit7 = MIL，低 7 位 = 已确认 DTC 数量
  ///  B: bit3 = 点火类型（0 汽油 / 1 柴油）；
  ///     bit2..0 = 失火 / 燃油系统 / 综合组件 的"支持"位；
  ///     bit6..4 = 这三项的"完成"位（1 = 已完成）
  ///  C: 机型专属监测的"支持"位图，D: 对应"完成"位图（1 = 已完成）
  ///  汽油位序：0 催化器 / 1 加热催化 / 2 EVAP / 3 二次空气 /
  ///       4 GPF / 5 氧传感器 / 6 氧传感器加热 / 7 EGR 或 VVT
  ///  柴油位序：0 NMHC / 1 NOx / 2 保留 / 3 增压 / 4 保留 /
  ///       5 排气传感器 / 6 DPF / 7 EGR 或 VVT
  static ReadinessReport? parseReadiness(String raw) {
    final body = payloadAfter(raw, '4101');
    if (body == null || body.length < 8) return null;
    final a = int.tryParse(body.substring(0, 2), radix: 16);
    final b = int.tryParse(body.substring(2, 4), radix: 16);
    final c = int.tryParse(body.substring(4, 6), radix: 16);
    final d = int.tryParse(body.substring(6, 8), radix: 16);
    if (a == null || b == null || c == null || d == null) return null;

    final diesel = (b & 0x08) != 0;
    final names = diesel
        ? const [
            'NMHC 催化器',
            'NOx / SCR',
            '',
            '增压压力',
            '',
            '排气传感器',
            '颗粒捕集器 DPF',
            'EGR / VVT',
          ]
        : const [
            '催化器',
            '加热催化器',
            '蒸发系统 EVAP',
            '二次空气',
            '汽油颗粒捕集器 GPF',
            '氧传感器',
            '氧传感器加热',
            'EGR / VVT',
          ];
    final monitors = <ReadinessMonitor>[];
    // 三项通用监测：失火 / 燃油系统 / 综合组件（支持 B0-B2，完成 B4-B6）。
    const base = ['失火监测', '燃油系统', '综合组件'];
    for (var i = 0; i < 3; i++) {
      if ((b & (1 << i)) == 0) continue;
      monitors.add(ReadinessMonitor(
        name: base[i],
        supported: true,
        complete: (b & (1 << (i + 4))) != 0,
      ));
    }
    for (var i = 0; i < 8; i++) {
      if ((c & (1 << i)) == 0) continue;
      if (names[i].isEmpty) continue;
      monitors.add(ReadinessMonitor(
        name: names[i],
        supported: true,
        complete: (d & (1 << i)) != 0,
      ));
    }
    return ReadinessReport(
      milOn: (a & 0x80) != 0,
      dtcCount: a & 0x7F,
      monitors: monitors,
    );
  }

  /// 冻结帧支持读取的 PID 及解码表（标签 / 单位）。
  static const Map<int, (String, String)> freezePids = {
    0x04: ('发动机负荷', '%'),
    0x05: ('冷却液温度', '°C'),
    0x06: ('短期燃油修正', '%'),
    0x07: ('长期燃油修正', '%'),
    0x0B: ('进气歧管压力', 'kPa'),
    0x0C: ('发动机转速', 'rpm'),
    0x0D: ('车速', 'km/h'),
    0x0F: ('进气温度', '°C'),
    0x10: ('空气流量', 'g/s'),
    0x11: ('节气门开度', '%'),
    0x1F: ('运行时间', 's'),
    0x21: ('故障灯亮起后里程', 'km'),
    0x2F: ('燃油液位', '%'),
    0x33: ('大气压', 'kPa'),
    0x42: ('控制模块电压', 'V'),
    0x46: ('环境温度', '°C'),
  };

  /// 解析 `42 <PID> 00 <data…>` 的冻结帧单项。
  static FreezeFrameField? parseFreezePid(String raw, int pid) {
    final hexPid = pid.toRadixString(16).toUpperCase().padLeft(2, '0');
    final body = payloadAfter(raw, '42$hexPid');
    if (body == null || body.length < 4) return null;
    // 跳过帧号（"00"），剩数据。
    final data = body.substring(2);
    final f = freezePids[pid];
    if (f == null) return null;
    final value = decodeFreezeValue(pid, data);
    if (value == null) return null;
    return FreezeFrameField(f.$1, value, f.$2);
  }

  /// 按 SAE J1979 解码冻结帧数据字节。
  static double? decodeFreezeValue(int pid, String data) {
    int? byteAt(int i) {
      if (data.length < (i + 1) * 2) return null;
      return int.tryParse(data.substring(i * 2, i * 2 + 2), radix: 16);
    }

    final a = byteAt(0);
    if (a == null) return null;
    final b = byteAt(1) ?? 0;
    switch (pid) {
      case 0x04:
      case 0x11:
      case 0x2F:
        return a * 100 / 255;
      case 0x05:
      case 0x0F:
      case 0x46:
        return a - 40;
      case 0x06:
      case 0x07:
        return (a - 128) * 100 / 128;
      case 0x0B:
      case 0x33:
        return a.toDouble();
      case 0x0C:
        return (a * 256 + b) / 4;
      case 0x0D:
        return a.toDouble();
      case 0x10:
        return (a * 256 + b) / 100;
      case 0x1F:
        return (a * 256 + b).toDouble();
      case 0x21:
        return (a * 256 + b).toDouble();
      case 0x42:
        return (a * 256 + b) / 1000;
      default:
        return null;
    }
  }

  /// 解析 `42 02 00 <DTC hi> <DTC lo>`（触发冻结帧的故障码）。
  static String? parseFreezeDtc(String raw) {
    final body = payloadAfter(raw, '420200');
    if (body == null || body.length < 4) return null;
    final b0 = int.tryParse(body.substring(0, 2), radix: 16);
    final b1 = int.tryParse(body.substring(2, 4), radix: 16);
    if (b0 == null || b1 == null) return null;
    if (b0 == 0 && b1 == 0) return null;
    return encodeDtc(b0, b1);
  }
}
