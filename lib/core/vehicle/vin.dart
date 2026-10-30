/// VIN（车架号）解析与车型匹配。
///
/// ELM327 返回的 Mode 09 02 响应形态极不统一：
///  - 关掉响应头（ATH0）+ 自动格式化（ATCAF1）：`49 02 01 4A 4D 31 ...`
///  - 关闭自动格式化（ATCAF0）：多帧被拆成 `0: ...` / `1: ...` 多行
///  - 带响应头（ATH1）：每行以 `7E8` 开头，后续帧带 ISO-TP 序号 `21`
///  - 不同适配器还会在末尾补 `55 55 55`（'U'）或 `00` 填充
/// 这里只做一件事：从任意形态里稳定取出 17 位 VIN，再按 WMI/车型代号匹配预设。
class VinInfo {
  const VinInfo({
    required this.vin,
    required this.wmi,
    required this.modelCode,
    required this.year,
  });

  /// 17 位车架号（已校验字符集）。
  final String vin;

  /// 世界制造厂代码（前 3 位）。
  final String wmi;

  /// 车型代号段（第 4–8 位），马自达这里通常是 `GH` / `GJ`。
  final String modelCode;

  /// 第 10 位解出的年款；无法解析时为 null。
  final int? year;

  static const Set<String> _allowed = {
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', //
    'P', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '0', '1', '2', //
    '3', '4', '5', '6', '7', '8', '9',
  };

  /// 年款编码（第 10 位）：2010 起是字母，之前是数字。
  static const Map<String, int> _yearCode = {
    '9': 2009, 'A': 2010, 'B': 2011, 'C': 2012, 'D': 2013, 'E': 2014,
    'F': 2015, 'G': 2016, 'H': 2017, 'J': 2018, 'K': 2019, 'L': 2020,
    'M': 2021, 'N': 2022, 'P': 2023, 'R': 2024, 'S': 2025, 'T': 2026,
  };

  /// 常见马自达 WMI（日本/美国/墨西哥/中国合资厂）。
  static const Set<String> _mazdaWmi = {
    'JM1', 'JMZ', 'JM6', 'JM7', '1YV', '4F2', '3MZ', 'MMZ', 'LFP', 'LVS',
  };

  /// 从任意 ELM327 响应文本中提取 VIN；失败返回 null。
  static VinInfo? parse(String raw) {
    if (raw.trim().isEmpty) return null;
    // 1. 逐行清洗：去 `0:` 帧号 → 去 CAN 头（7E8 / 18DAF1xx）→ 去 ISO-TP 序号。
    //    真实路径是 ATH0+ATCAF1（ELM 已重组），这里只是兼容 ATH1 抓包文本。
    final cleaned = raw
        .split(RegExp(r'[\r\n]+'))
        .map((l) {
          var s = l.replaceFirst(RegExp(r'^\s*[0-9A-Fa-f]{1,3}\s*:'), '');
          s = s.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
          // CAN 11 位头（7E0–7E8）：后面紧跟 PCI 字节时才算头。
          final hadHeader = RegExp(r'^(?:18[0-9A-F]{6}|7E[0-9A-F])(?=[0-3][0-9A-F])')
              .hasMatch(s);
          if (hadHeader) {
            s = s.replaceFirst(RegExp(r'^(?:18[0-9A-F]{6}|7E[0-9A-F])'), '');
            // 有头时才可能是原始 ISO-TP 帧，去掉首帧/连续帧的 PCI 字节。
            s = s.replaceFirst(RegExp(r'^[0-3][0-9A-F]'), '');
          }
          return s;
        })
        .join();

    // 2. 定位 VIN 服务应答 49 02 01。
    final idx = cleaned.indexOf('490201');
    if (idx < 0) return null;
    var body = cleaned.substring(idx + 6);

    // 3. 逐字节转 ASCII，遇到非法字符就停（末尾填充 55/00 会被自然截断）。
    final buf = StringBuffer();
    for (var i = 0; i + 2 <= body.length; i += 2) {
      final code = int.tryParse(body.substring(i, i + 2), radix: 16);
      if (code == null) break;
      final ch = String.fromCharCode(code);
      if (!_allowed.contains(ch)) {
        if (buf.isNotEmpty) break; // VIN 之后出现填充，收工
        continue; // 前导的 ISO-TP 头/计数，跳过
      }
      buf.write(ch);
      if (buf.length == 17) break;
    }
    final vin = buf.toString();
    return _validate(vin);
  }

  static VinInfo? _validate(String vin) {
    if (vin.length != 17) return null;
    if (!vin.split('').every(_allowed.contains)) return null;
    // 至少带 4 位数字，避免把纯字母的噪声当 VIN。
    final digits = vin.split('').where((c) => int.tryParse(c) != null).length;
    if (digits < 4) return null;
    return VinInfo(
      vin: vin,
      wmi: vin.substring(0, 3),
      modelCode: vin.substring(3, 8),
      year: _yearCode[vin[9]],
    );
  }

  /// 根据 VIN 匹配内置车型；识别不出返回 null（保持用户手选，不乱猜）。
  ///
  /// 马自达 6：GH 代（2002–2013，含 2011 款"普马"）与 GJ 代（2014+ 创驰蓝天）
  /// 的车型代号直接写在第 4–5 位，比年款更可靠（跨年款生产很常见）。
  String? matchProfileId() {
    final isMazda = _mazdaWmi.contains(wmi) || wmi.startsWith('L');
    if (!isMazda) return null;
    final code = modelCode;
    if (code.startsWith('GJ') || code.startsWith('GL')) return 'mazda6_gj';
    if (code.startsWith('GH')) return 'mazda6_2011';
    // 代号缺失时用年款兜底：2013 及以前按 GH，2014 起按 GJ。
    final y = year;
    if (y != null) {
      if (y <= 2013) return 'mazda6_2011';
      if (y <= 2022) return 'mazda6_gj';
    }
    return null;
  }

  /// 给 UI 用的一行摘要。
  String get summary {
    final y = year == null ? '' : ' · ${year}款';
    return '$vin$y';
  }
}
