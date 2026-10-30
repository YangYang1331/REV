/// ELM327 总线协议纯逻辑解析（无 Flutter / 无 IO，可单测）。
///
/// 背景：旧版握手固定 `ATSP6`（ISO15765-4 CAN 11bit 500k，马6 协议），
/// 遇到 ISO9141 / KWP2000 / CAN 29bit 的车或适配器就直接连不上。
/// v2.13.0 改为 `ATSP0` 自动探测：初始化后用 `ATDPN` 读当前激活协议号，
/// 由本类把原始应答映射到 [ObdProtocol] 枚举；UI 不做手动选择。
///
/// ELM322/327 ATSP 协议号（V1.5 ~ V2.3 通用）：
///  0 = Automatic（自动）
///  1 = SAE J1850 PWM  (41.6k)
///  2 = SAE J1850 VPW  (10.4k)
///  3 = ISO 9141-2     (5 baud init, 10.4k)
///  4 = ISO 14230-4 KWP (5 baud init, 10.4k)
///  5 = ISO 14230-4 KWP fast init
///  6 = ISO 15765-4 CAN 11bit 500k  ← 马6
///  7 = ISO 15765-4 CAN 29bit 500k
///  8 = ISO 15765-4 CAN 11bit 250k
///  9 = ISO 15765-4 CAN 29bit 250k
///  A = SAE J1939 11bit 250k（部分固件）
///  B/C = 用户可编程
library;

/// 识别出的总线协议。
enum ObdProtocol {
  /// SAE J1850 PWM（美系老车常用）。
  saeJ1850Pwm,

  /// SAE J1850 VPW（通用老车）。
  saeJ1850Vpw,

  /// ISO 9141-2（亚系老车 / 欧系老车 K-line）。
  iso9141,

  /// ISO 14230-4 KWP2000 5-baud init。
  kwp2000_5baud,

  /// ISO 14230-4 KWP2000 fast init。
  kwp2000Fast,

  /// ISO 15765-4 CAN 11bit 500k —— 2008+ 汽油车主流，马6 落在这里。
  can11bit500,

  /// ISO 15765-4 CAN 29bit 500k（欧系 / 重卡）。
  can29bit500,

  /// ISO 15765-4 CAN 11bit 250k。
  can11bit250,

  /// ISO 15765-4 CAN 29bit 250k。
  can29bit250,

  /// SAE J1939（重卡柴油）。
  saeJ1939,

  /// 未知 / 未读到。
  unknown;

  /// 是否是 CAN 协议（影响批量请求帧格式假设；ISO15765 才支持多 PID 拼接）。
  bool get isCan =>
      this == can11bit500 ||
      this == can29bit500 ||
      this == can11bit250 ||
      this == can29bit250 ||
      this == saeJ1939;

  /// 是否是马6 目标协议（用于日志/自检提示）。
  bool get isMazda6Target => this == can11bit500;

  String get label {
    switch (this) {
      case ObdProtocol.saeJ1850Pwm:
        return 'SAE J1850 PWM 41.6k';
      case ObdProtocol.saeJ1850Vpw:
        return 'SAE J1850 VPW 10.4k';
      case ObdProtocol.iso9141:
        return 'ISO 9141-2';
      case ObdProtocol.kwp2000_5baud:
        return 'ISO 14230 KWP2000 (5 baud init)';
      case ObdProtocol.kwp2000Fast:
        return 'ISO 14230 KWP2000 (fast init)';
      case ObdProtocol.can11bit500:
        return 'CAN 11-bit 500k (ISO 15765-4)';
      case ObdProtocol.can29bit500:
        return 'CAN 29-bit 500k (ISO 15765-4)';
      case ObdProtocol.can11bit250:
        return 'CAN 11-bit 250k (ISO 15765-4)';
      case ObdProtocol.can29bit250:
        return 'CAN 29-bit 250k (ISO 15765-4)';
      case ObdProtocol.saeJ1939:
        return 'SAE J1939 250k';
      case ObdProtocol.unknown:
        return '未知协议';
    }
  }
}

/// `ATDPN`（读当前协议）应答解析结果。
class ProtocolInfo {
  const ProtocolInfo({
    required this.protocol,
    this.rawCode,
    this.autoSelected = false,
  });

  /// 识别出的协议。
  final ObdProtocol protocol;

  /// ELM 返回的原始协议号字符（'6' / '7' ...），未读到为 null。
  final String? rawCode;

  /// 是否由 ATSP0 自动探测选出（而非用户固定）。
  final bool autoSelected;
}

/// 纯函数：把 ATDPN 应答文本映射到 [ObdProtocol]。
///
/// ATDPN 典型应答（LineFramer 已 trim / 大写 / 去空白）：
///  - `6`      → 已固定协议 6（CAN 11bit 500k）
///  - `A6`     → ATSP0 自动模式下选中了协议 6（前缀 A = automatic）
///  - `7`/`B7` → 29bit 500k
///  - `?` / `NO DATA` / 空 → unknown
///
/// 兼容 ELM 第三方克隆固件：有的会回 `DPN 6\r`、带提示符残留 `6>` 等；
/// 这里只抽第一个十六进制字符判定，多余噪声忽略。
ObdProtocol protocolFromElmCode(String codeChar) {
  switch (codeChar.toUpperCase()) {
    case '1':
      return ObdProtocol.saeJ1850Pwm;
    case '2':
      return ObdProtocol.saeJ1850Vpw;
    case '3':
      return ObdProtocol.iso9141;
    case '4':
      return ObdProtocol.kwp2000_5baud;
    case '5':
      return ObdProtocol.kwp2000Fast;
    case '6':
      return ObdProtocol.can11bit500;
    case '7':
      return ObdProtocol.can29bit500;
    case '8':
      return ObdProtocol.can11bit250;
    case '9':
      return ObdProtocol.can29bit250;
    case 'A':
      return ObdProtocol.saeJ1939;
    default:
      return ObdProtocol.unknown;
  }
}

/// 解析 `ATDPN` 的完整应答行（可能含 `A` 自动前缀、噪声字符）。
ProtocolInfo parseActiveProtocol(String rawLine) {
  if (rawLine.isEmpty) {
    return const ProtocolInfo(protocol: ObdProtocol.unknown);
  }
  // 只保留 hex 字符；A 既可能是"自动前缀"也可能是协议号 A（J1939），
  // 约定：长度 == 1 时是协议号；长度 >= 2 且首字符为 A 时，首字符视为 auto 标记。
  final cleaned = rawLine
      .toUpperCase()
      .replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (cleaned.isEmpty) {
    return const ProtocolInfo(protocol: ObdProtocol.unknown);
  }
  var auto = false;
  var codePart = cleaned;
  if (cleaned.length >= 2 && cleaned.startsWith('A')) {
    auto = true;
    codePart = cleaned.substring(1);
  }
  final codeChar = codePart.substring(0, 1);
  return ProtocolInfo(
    protocol: protocolFromElmCode(codeChar),
    rawCode: codeChar,
    autoSelected: auto,
  );
}

/// 纯函数：从 ATZ 应答里粗判适配器芯片型号（日志用，不影响连接逻辑）。
/// 常见应答：`ELM327 v1.5` / `STN1110` / `OBDKey` / `BLE327` 等。
String describeAdapterAti(String rawLine) {
  var s = rawLine.trim();
  if (s.isEmpty) return '未知适配器';
  // 去掉提示符与尾部版本号噪声
  s = s.replaceAll('>', '').trim();
  if (s.length > 40) s = s.substring(0, 40);
  return s;
}
