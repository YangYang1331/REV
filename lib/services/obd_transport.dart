import 'dart:async';

/// 统一 OBD 传输层抽象。
///
/// BLE（Nordic UART）与 USB 有线串口（CH340/CP210x/PL230x/FTDI/CDC）
/// 都实现本接口，因此 ELM327 初始化、PID 轮询、响应解析在 [ObdService] 里
/// 完全共用一套逻辑，传输介质对上层透明。
///
/// 实现层职责：
///  - 打开设备 / 申请权限 / 设定波特率；
///  - 把底层字节流（可能粘包、分包）喂给 [LineFramer]，产出“已按行切分、
///    去空白、大写”的响应行，通过 [onLine] 吐给上层；
///  - writeString 自动补 '\r'（上层不要再补）；
///  - 检测到物理断开（BLE 掉线 / USB 拔出）时往 [onDisconnected] 发一个事件，
///    由上层做安全重连。
abstract class ObdTransport {
  /// 供 UI / 日志展示的名字（如 "BLE ELM327" / "USB CH340 (1A86:7523)"）。
  String get displayName;

  bool get isConnected;

  /// 已按行 / 提示符切分、trim、转大写的完整响应行。
  /// 例如 ELM 回 `41 0C 1F 88\r>` 会产出一行 `410C1F88`。
  Stream<String> get onLine;

  /// 物理断开事件（用户主动 disconnect 不触发；只在意外掉线时触发）。
  Stream<void> get onDisconnected;

  /// 连接（含权限申请 / 打开设备 / 波特率握手）。成功返回 true。
  Future<bool> connect();

  /// 写一行命令，实现层自动补 '\r'。
  Future<void> writeString(String s);

  Future<void> disconnect();

  void dispose();

  /// 供 AppStore 记忆的连接标识（BLE=remoteId，USB=vid:pid）；不需记忆返回 null。
  String? get storageId => null;

  /// 供 AppStore 记忆的显示名。
  String? get storageLabel => null;
}

/// 通用串口 / BLE 组帧器：处理粘包与分包。
///
/// 以 '\r'、'\n'、以及 ELM 的命令提示符 '>' 作为行结束符；
/// 每行 trim 后若非空则转大写吐给 [onLine]。
/// BLE 与 USB 共用本类，保证两边组帧 / 解析完全一致（任务硬约束）。
class LineFramer {
  LineFramer({required this.onLine});

  /// 每得到一条完整响应行回调一次（已 trim、大写）。
  final void Function(String line) onLine;

  final StringBuffer _buf = StringBuffer();
  bool _closed = false;

  /// 喂入一段原始字节（BLE notify / USB inputStream 都用它）。
  void addBytes(List<int> bytes) {
    if (_closed) return;
    _buf.write(String.fromCharCodes(bytes));
    _drain();
  }

  /// 喂入一段文本（测试 FakeTransport 直接用）。
  void addText(String text) {
    if (_closed) return;
    _buf.write(text);
    _drain();
  }

  void _drain() {
    var s = _buf.toString();
    var idx = _firstDelim(s);
    while (idx >= 0) {
      // 去空格 + 大写（与 PidParser._clean 一致，BLE/USB 同一路径）。
      var chunk = s.substring(0, idx).trim().toUpperCase();
      chunk = chunk.replaceAll(RegExp(r'\s+'), '');
      if (chunk.isNotEmpty) onLine(chunk);
      s = s.substring(idx + 1);
      idx = _firstDelim(s);
    }
    _buf
      ..clear()
      ..write(s);
  }

  /// 找到最早出现的行结束符：'\r'、'\n'、'<'... 即 ELM 提示符 '>'。
  int _firstDelim(String s) {
    var best = -1;
    for (final ch in const ['\r', '\n', '>']) {
      final i = s.indexOf(ch);
      if (i >= 0 && (best < 0 || i < best)) best = i;
    }
    return best;
  }

  /// 丢弃未组完的残留（重连 / 断连时调用，避免旧数据污染新会话）。
  void reset() {
    _buf.clear();
  }

  void close() {
    _closed = true;
    _buf.clear();
  }
}
