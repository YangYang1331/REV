/// Mode 01 现行数据 PID（SAE J1979 / ISO 15031-5 公开标准）。
enum Pid {
  rpm(0x0C, 2, Pid.kindRpm),
  speed(0x0D, 1, Pid.kindSpeed),
  coolant(0x05, 1, Pid.kindTemp),
  intakeTemp(0x0F, 1, Pid.kindTemp),
  ambient(0x46, 1, Pid.kindTemp),
  map(0x0B, 1, Pid.kindRaw),
  engineLoad(0x04, 1, Pid.kindPct),
  absLoad(0x43, 2, Pid.kindAbsLoad),
  throttle(0x11, 1, Pid.kindPct),
  maf(0x10, 2, Pid.kindMaf),
  fuelLevel(0x2F, 1, Pid.kindPct),
  fuelRate(0x5E, 2, Pid.kindFuelRate),
  ltft(0x07, 1, Pid.kindLtft),
  ignAdv(0x0E, 1, Pid.kindIgnAdv),
  catTemp(0x3C, 2, Pid.kindCatTemp),
  fuelRail(0x22, 2, Pid.kindFuelRail),
  voltage(0x42, 2, Pid.kindVoltage);

  const Pid(this.code, this.expectBytes, this.decode);
  final int code;
  final int expectBytes;
  final double Function(List<int>) decode;

  String get hex => code.toRadixString(16).padLeft(2, '0').toUpperCase();
  String get request => '01${hex}';

  static double kindRpm(List<int> b) => (b[0] * 256 + b[1]) / 4.0;
  static double kindSpeed(List<int> b) => b[0].toDouble();
  static double kindTemp(List<int> b) => b[0] - 40.0;
  static double kindRaw(List<int> b) => b[0].toDouble();
  static double kindPct(List<int> b) => b[0] * 100.0 / 255.0;
  static double kindMaf(List<int> b) => (b[0] * 256 + b[1]) / 100.0;
  static double kindAbsLoad(List<int> b) =>
      (b[0] * 256 + b[1]) * 100.0 / 25500.0;
  static double kindFuelRate(List<int> b) => (b[0] * 256 + b[1]) * 0.05;
  static double kindVoltage(List<int> b) => (b[0] * 256 + b[1]) / 1000.0;
  static double kindLtft(List<int> b) => (b[0] - 128) * 100.0 / 128.0;
  static double kindIgnAdv(List<int> b) => b[0] / 2.0 - 64.0;
  static double kindCatTemp(List<int> b) =>
      (b[0] * 256 + b[1]) / 10.0 - 40.0;
  static double kindFuelRail(List<int> b) =>
      (b[0] * 256 + b[1]) * 0.1 / 1000.0; // MPa
}

class PidParser {
  /// 清洗 ELM327 噪声，保留十六进制负载。
  static String _clean(String raw) {
    var s = raw;
    const noise = [
      '>',
      'SEARCHING...',
      'SEARCHING',
      'STOPPED',
      'NO DATA',
      'UNABLE TO CONNECT',
      'BUS INIT',
      'ERROR',
      '?',
    ];
    for (final n in noise) {
      s = s.replaceAll(n, '');
    }
    s = s.replaceAll(RegExp(r'\s+'), '').trim();
    return s;
  }

  /// 单 PID 解析，返回数据字节；失败 null。
  static List<int>? parseResponse(Pid pid, String raw) {
    final s = _clean(raw);
    if (s.length < 4 + pid.expectBytes * 2) return null;
    final marker = '41${pid.hex}';
    final idx = s.indexOf(marker);
    if (idx < 0) return null;
    final start = idx + marker.length;
    if (start + pid.expectBytes * 2 > s.length) return null;
    return _bytes(s, start, pid.expectBytes);
  }

  /// 批量响应解析：一条 "010C0D" 返回 41 0C .. .. 0D ..，遍历所有 41XX。
  static Map<Pid, double> parseMulti(String raw, List<Pid> pids) {
    final s = _clean(raw);
    final out = <Pid, double>{};
    for (final pid in pids) {
      final marker = '41${pid.hex}';
      final idx = s.indexOf(marker);
      if (idx < 0) continue;
      final start = idx + marker.length;
      if (start + pid.expectBytes * 2 > s.length) continue;
      final bytes = _bytes(s, start, pid.expectBytes);
      if (bytes == null) continue;
      try {
        out[pid] = pid.decode(bytes);
      } catch (_) {}
    }
    return out;
  }

  static List<int>? _bytes(String s, int start, int n) {
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      final v = int.tryParse(s.substring(start + i * 2, start + i * 2 + 2),
          radix: 16);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  /// code(hex 数值) -> Pid 反查表，供批量响应按位置顺序解析。
  static final Map<int, Pid> _byCode = {
    for (final p in Pid.values) p.code: p,
  };

  /// 位置序贯解析 ISO15765/SAE J1979 多 PID 批量响应。
  ///
  /// 请求形如 "010C0D051104"（mode 01 + 一串 PID 字节），正响应以 "41" 开头，
  /// 之后按请求顺序重复 [PID][数据...]，例如：
  ///   `410CA8F00D3C055011200432`
  ///     = 41 | 0C A8 F0 | 0D 3C | 05 50 | 11 20 | 04 32
  /// 与 [parseMulti]（要求每个 PID 都带 "41XX" 前缀，仅适用于多帧带响应头的情形）
  /// 不同，本方法按字节流顺序走，适配 ATCAF0/ATH0 关头后的紧凑拼接响应。
  /// 非法 / 缺字节段自动跳过，绝不抛异常。
  static Map<Pid, double> parseMultiSequential(String raw) {
    final out = <Pid, double>{};
    var s = _clean(raw);
    if (!s.startsWith('41')) return out;
    var pos = 2;
    while (pos + 2 <= s.length) {
      final codeStr = s.substring(pos, pos + 2);
      final code = int.tryParse(codeStr, radix: 16);
      if (code == null) break;
      final pid = _byCode[code];
      if (pid == null) break; // 未知 PID，对齐失效，停止
      pos += 2;
      if (pos + pid.expectBytes * 2 > s.length) break; // 数据不完整
      final data = _bytes(s, pos, pid.expectBytes);
      pos += pid.expectBytes * 2;
      if (data == null) break;
      try {
        out[pid] = pid.decode(data);
      } catch (_) {}
    }
    return out;
  }
}

/// Mode 01 PID 支持位图（0100/0120/0140/0160）
class PidDiscovery {
  /// 解析四组支持位图，返回受支持 PID 编号集合（1..255）。
  static Set<int> parseSupported(List<String> frames) {
    final supported = <int>{};
    for (var gi = 0; gi < frames.length; gi++) {
      final bytes = _parseBitmap(frames[gi], gi * 0x20);
      if (bytes == null) continue;
      for (var bit = 0; bit < 32; bit++) {
        final byteIdx = bit ~/ 8;
        final bitVal = 7 - (bit % 8);
        if (((bytes[byteIdx]) >> bitVal) & 1 == 1) {
          final pid = gi * 32 + bit + 1;
          if (pid >= 1 && pid <= 255) supported.add(pid);
        }
      }
    }
    return supported;
  }

  static List<int>? _parseBitmap(String raw, int groupBase) {
    var s = raw.replaceAll(RegExp(r'[\s>\r\n?]'), '');
    s = s.replaceAll('SEARCHING...', '').replaceAll('NO DATA', '');
    final marker = '41${groupBase.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    final idx = s.indexOf(marker);
    if (idx < 0) return null;
    final start = idx + marker.length;
    if (start + 8 > s.length) return null;
    final out = <int>[];
    for (var i = 0; i < 4; i++) {
      final v =
          int.tryParse(s.substring(start + i * 2, start + i * 2 + 2), radix: 16);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  /// 解析 Mode 09 PID 02 的 VIN（17 位）。
  static String? parseVin(String raw) {
    final s = raw
        .replaceAll(RegExp(r'[\s>\r\n?]'), '')
        .replaceAll('SEARCHING...', '')
        .replaceAll('NO DATA', '');
    final idx = s.indexOf('4902');
    if (idx < 0) return null;
    var p = idx + 4;
    if (p + 2 <= s.length) {
      final b = s.substring(p, p + 2);
      if (b == '01' || b == '00') p += 2;
    }
    final sb = StringBuffer();
    while (p + 2 <= s.length) {
      final b = int.tryParse(s.substring(p, p + 2), radix: 16);
      if (b == null) break;
      if (b >= 0x20 && b <= 0x7E) sb.writeCharCode(b);
      p += 2;
    }
    final vin = sb.toString().trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return vin.length >= 11 ? vin : null;
  }
}
