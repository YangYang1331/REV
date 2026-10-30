import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:obd_dashboard/core/obd/obd_pid.dart';
import 'package:obd_dashboard/core/obd/obd_protocol.dart';
import 'package:obd_dashboard/core/obd/pid_sanity.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/vehicle/vin.dart';
import 'package:obd_dashboard/models/obd_data.dart';
import 'package:obd_dashboard/services/obd_transport.dart';
import 'package:obd_dashboard/services/sound_service.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';

/// 连接阶段。
enum ObdConnStage {
  idle,
  scanning,
  connecting,
  initializing,
  polling,
  reconnecting,
  disconnected,
}

/// 连接状态快照（供 UI / 自检测页观察）。
@immutable
class ObdConnState {
  const ObdConnState({
    required this.stage,
    this.lastError,
    this.reconnectAttempt = 0,
  });

  final ObdConnStage stage;
  final String? lastError;
  final int reconnectAttempt;

  bool get isLive =>
      stage == ObdConnStage.connecting ||
      stage == ObdConnStage.initializing ||
      stage == ObdConnStage.polling ||
      stage == ObdConnStage.reconnecting;

  ObdConnState copyWith({
    ObdConnStage? stage,
    String? lastError,
    int? reconnectAttempt,
  }) =>
      ObdConnState(
        stage: stage ?? this.stage,
        lastError: lastError ?? this.lastError,
        reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      );
}

/// 一条命令的结果。
class _CmdResult {
  const _CmdResult({required this.text, required this.timedOut});
  final String text;
  final bool timedOut;
  bool get hasData => !timedOut && text.isNotEmpty;
}

/// 真实 ELM327 OBD 数据服务（BLE / USB 共用）。
///
/// 负责：连接 [ObdTransport] → ELM327 初始化 → PID 轮询 → 解析 → 推入 TelemetryService。
/// 传输层通过构造/[connect] 注入，本类对 BLE 与 USB 走完全相同的初始化、轮询、解析。
/// 意外断开按指数退避自动重连；用户主动断开则不重连。
class ObdService {
  ObdService(this._telemetry);

  final TelemetryService _telemetry;
  ObdTransport? _transport;
  StreamSubscription<String>? _lineSub;
  StreamSubscription<void>? _discSub;

  Timer? _reconnectTimer;
  bool _running = false;
  bool _connected = false;
  bool _wantConnected = false;
  String _status = 'idle';
  String get status => _status;
  bool get isConnected => _connected;

  /// 连接状态（UI 监听此 ValueNotifier）。
  final ValueNotifier<ObdConnState> connState =
      ValueNotifier(const ObdConnState(stage: ObdConnStage.idle));

  int _reconnectAttempt = 0;

  // 当前帧缓存（各 PID 最新值）
  final Map<Pid, double> _values = {};
  int _slowIndex = 0;

  /// 核心高频 PID（每轮都问；一次批量请求）。马6关键参数。
  static const List<Pid> _fastPids = [
    Pid.rpm, // 010C 转速
    Pid.speed, // 010D 车速
    Pid.coolant, // 0105 水温
    Pid.throttle, // 0111 油门
    Pid.engineLoad, // 0104 发动机负荷
  ];

  /// 次要低频 PID（轮流问，不每轮全读）。
  static const List<Pid> _slowPids = [
    Pid.map,
    Pid.maf,
    Pid.fuelLevel,
    Pid.voltage,
    Pid.intakeTemp,
    Pid.oilTemp,
    Pid.ltft,
    Pid.ignAdv,
    Pid.ambient,
    Pid.absLoad,
    Pid.fuelRate,
  ];

  // ---- 响应驱动命令 correlator ----
  Completer<_CmdResult>? _pending;
  String? _pendingExpect; // 等待出现的标记（如 "410C" / "OK"）；null=首行即回
  final List<String> _pendingBuf = [];
  Timer? _pendingTimer;
  Stopwatch? _sw;

  /// 近期往返耗时 EMA（毫秒），用于自适应超时。
  double _rttMs = 40;
  int _consecutiveTimeouts = 0;

  /// ECU 是否支持 ISO15765 多 PID 批量请求（启动时探测一次）。
  bool _batchSupported = false;

  /// ATSP0 自动探测到的当前总线协议（马6 应为 can11bit500）。
  ObdProtocol _activeProtocol = ObdProtocol.unknown;
  ObdProtocol get activeProtocol => _activeProtocol;

  /// 适配器描述（ATZ 应答首行，日志/自检展示）。
  String _adapterName = '';
  String get adapterName => _adapterName;

  /// 外部可注入的日志 sink（落日志/行程记录用）；默认 debugPrint。
  void Function(String msg)? logSink;

  /// 重连次数上限：超过后停止自动重连，等待用户手动重连（避免死循环耗电）。
  static const int maxReconnectAttempts = 8;

  /// 握手阶段每步重试次数。
  static const int handshakeRetries = 2;

  void _log(String msg) {
    final sink = logSink;
    if (sink != null) {
      try {
        sink(msg);
        return;
      } catch (_) {}
    }
    debugPrint('[OBD] $msg');
  }

  void _setState(ObdConnStage s, {String? error, int? attempt}) {
    _status = s.name;
    connState.value = connState.value.copyWith(
      stage: s,
      lastError: error,
      reconnectAttempt: attempt,
    );
  }

  /// 用户发起连接：注入 transport 并连接，成功后自动重连生效。
  Future<bool> connect(ObdTransport transport) async {
    // 切换数据源：先断开旧传输，同一时刻只激活一个。
    await _teardownTransport();
    _transport = transport;
    _wireTransport();
    _wantConnected = true;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    return _doConnect();
  }

  /// 订阅 transport 的行流与物理断开事件。
  void _wireTransport() {
    _lineSub?.cancel();
    _discSub?.cancel();
    _lineSub = _transport?.onLine.listen(_onLine);
    _discSub = _transport?.onDisconnected.listen((_) => _onPhysicalDrop());
  }

  /// 实际连接 + 初始化（可被重连复用）。
  Future<bool> _doConnect() async {
    final t = _transport;
    if (t == null || !_wantConnected) return false;
    _setState(ObdConnStage.connecting);
    final ok = await t.connect();
    if (!ok) {
      _setState(ObdConnStage.disconnected, error: '${t.displayName} 连接失败');
      _scheduleReconnect('连接失败');
      return false;
    }
    _setState(ObdConnStage.initializing);
    await _initElm();
    // 探测批量请求能力（ISO15765 单帧可带多 PID）。
    await _probeBatch();
    _connected = true;
    _reconnectAttempt = 0;
    _consecutiveTimeouts = 0;
    _setState(ObdConnStage.polling);
    _startPolling();
    // 记录为已知设备（下次可自动连）
    try {
      final id = t.storageId;
      if (id != null) {
        await AppStore.instance.setKnownDevice(id, t.storageLabel ?? id);
      }
    } catch (_) {}
    // 连接成功提示音
    try {
      SoundService.instance.playConnected();
    } catch (_) {}
    // OBD 真实连接成功 → 把保活前台服务升级为 connectedDevice。
    try {
      await const MethodChannel('rev/foreground')
          .invokeMethod('onObdConnected');
    } catch (_) {}
    return true;
  }

  /// 物理意外掉线（用户仍想连）→ 安全重连。
  void _onPhysicalDrop() {
    if (!_wantConnected) return;
    if (!_connected && !_running) return;
    _connected = false;
    _running = false;
    _cancelPending();
    _values.clear();
    try {
      _telemetry.onObdDisconnected();
    } catch (_) {}
    _scheduleReconnect('连接已断开');
  }

  /// 指数退避重连：1→2→4→8→16→30s 封顶。
  ///
  /// 达到 [maxReconnectAttempts] 后不再“放弃”，而是转为每 60 秒一次的低频探测：
  /// 开车途中熄火再启动、适配器断电重插、地库出来恢复信号，这些场景都在
  /// 退避窗口之外，直接停止重连等于让用户手动跑去连接页（Torque 的老毛病）。
  void _scheduleReconnect(String error) {
    if (!_wantConnected) return;
    _reconnectAttempt++;
    if (_reconnectAttempt > maxReconnectAttempts) {
      _log('自动重连 $maxReconnectAttempts 次未成功，转为 60s 低频探测');
      _setState(ObdConnStage.disconnected,
          error: '$error（已转低频重试，可到连接页手动重连）',
          attempt: _reconnectAttempt);
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 60), () async {
        if (!_wantConnected) return;
        _reconnectAttempt = 1; // 重新走一轮快速退避
        await _doConnect();
      });
      return;
    }
    final sec = (1 << _reconnectAttempt).clamp(1, 30);
    _setState(ObdConnStage.reconnecting,
        error: error, attempt: _reconnectAttempt);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: sec), () async {
      if (!_wantConnected) return;
      await _doConnect();
    });
  }

  /// ELM327 初始化：每条连接只做一次，响应驱动（不等固定延时）。
  ///
  /// v2.13.0：固定 ATSP6 → ATSP0 自动探测；初始化后用 ATDPN 回读当前协议，
  /// 跨协议适配器/车（ISO9141/KWP2000/CAN29bit）也能连上；马6 自动落到
  /// CAN 11bit 500k。每步失败重试 [handshakeRetries] 次，命令超时分级。
  Future<void> _initElm() async {
    // 握手阶段超时（适配器复位慢、协议协商慢），比轮询长。
    const handshakeTimeout = 1500;

    // 1. 复位 + 读回适配器型号（ATZ 后 ELM 回 `ELM327...`）。
    final atz = await _sendCmd('ATZ', timeoutMs: handshakeTimeout);
    _adapterName = describeAdapterAti(atz.text);
    _log('适配器复位：$_adapterName');
    await Future.delayed(const Duration(milliseconds: 400));

    // 2. 基础设置（关回显/换行/空格/响应头），逐条等 OK。
    final baseCmds = ['ATE0', 'ATL0', 'ATS0', 'ATH0'];
    for (final c in baseCmds) {
      await _sendWithRetry(c, expect: 'OK', timeoutMs: 600);
    }

    // 3. 自动协议探测：ATSP0 让 ELM 自己扫总线。
    //    首次发可能 BUS INIT 慢，给更长超时；失败重试。
    await _sendWithRetry('ATSP0', expect: 'OK', timeoutMs: 2000);

    // 4. 让总线初始化一次（发个最低优先级探测命令触发 ECU 应答）。
    //    发 0100 等 41 响应，触发协议协商；超时也不致命（ATSP0 已锁协议）。
    await _sendCmd('0100', expectMarker: '41', timeoutMs: 2000);

    // 5. 回读当前激活协议（ATDPN）。
    final proto = await _sendCmd('ATDPN', timeoutMs: 600);
    final info = parseActiveProtocol(proto.text);
    _activeProtocol = info.protocol;
    _log('自动协议探测：${info.protocol.label}'
        '${info.autoSelected ? "（自动）" : ""} raw=${info.rawCode ?? "-"}');

    // 6. 总线超时 + 紧凑帧格式（轮询阶段用）。
    await _sendWithRetry('ATST20', expect: 'OK', timeoutMs: 400);
    await _sendWithRetry('ATCAF0', expect: 'OK', timeoutMs: 400);
  }

  /// 带重试的 AT 命令：每步失败重试 [handshakeRetries] 次；最终失败记日志不抛。
  Future<_CmdResult> _sendWithRetry(String cmd,
      {required String expect, required int timeoutMs}) async {
    _CmdResult last = const _CmdResult(text: '', timedOut: true);
    for (var i = 0; i <= handshakeRetries; i++) {
      last = await _sendCmd(cmd, expectMarker: expect, timeoutMs: timeoutMs);
      if (last.hasData) return last;
      _log('命令 $cmd 第 ${i + 1} 次未回 $expect，重试…');
    }
    _log('命令 $cmd 多次失败，继续后续流程');
    return last;
  }

  /// 探测 ECU 是否支持多 PID 批量请求；不支持则回退单 PID。
  Future<void> _probeBatch() async {
    final req = '01${_fastPids.map((p) => p.hex).join()}';
    final r = await _sendCmd(req, expectMarker: '41', timeoutMs: _timeoutMs());
    if (!r.hasData) {
      _batchSupported = false;
      return;
    }
    final m = PidParser.parseMultiSequential(r.text);
    _batchSupported = m.isNotEmpty;
    m.forEach(_putValue);
  }

  /// 把一个解码后的值写入 _values，先过物理范围 + 跳变合理性；
  /// 坏帧直接丢弃（不覆盖上一好值），避免仪表飞天。
  void _putValue(Pid pid, double v) {
    final prev = _values[pid];
    if (!PidSanity.accept(pid, prev, v)) {
      _log('坏帧丢弃：${pid.name} 上一帧=$prev 新值=$v');
      return;
    }
    _values[pid] = v;
  }

  /// 自适应命令超时：以近期 RTT 的 3 倍为基线，夹在 [120, 800]ms。
  int _timeoutMs() => (_rttMs * 3).clamp(120, 800).round();

  /// 全局命令锁：ELM327 一次只能跑一条命令，轮询与 UI 手工命令必须排队，
  /// 否则手工命令会被轮询线程“抢答”，收到的是上一条 PID 的响应。
  Future<void> _cmdLock = Future.value();

  /// 发送一条命令，等待匹配响应或超时。响应驱动：命中标记立即返回。
  Future<_CmdResult> _sendCmd(String cmd,
      {String? expectMarker, int? timeoutMs}) async {
    final t = _transport;
    if (t == null) return const _CmdResult(text: '', timedOut: true);
    final prev = _cmdLock;
    final gate = Completer<void>();
    _cmdLock = gate.future;
    try {
      await prev;
      // 排队期间可能已断开 / 换了传输，直接失败。
      if (t != _transport) return const _CmdResult(text: '', timedOut: true);
      final completer = Completer<_CmdResult>();
      _pending = completer;
      _pendingExpect = expectMarker;
      _pendingBuf.clear();
      _sw = Stopwatch()..start();
      final to = timeoutMs ?? _timeoutMs();
      _pendingTimer?.cancel();
      _pendingTimer = Timer(Duration(milliseconds: to),
          () => _finishPending(timedOut: true));
      try {
        await t.writeString(cmd);
      } catch (_) {
        _finishPending(timedOut: true);
      }
      return await completer.future;
    } finally {
      gate.complete();
    }
  }

  // ── 原始命令 / 厂商扩展数据（Mode 22） ──

  /// 手工发送一条十六进制命令（如 `010C`、`0902`、`2200`），返回 ECU 原文。
  /// 供诊断页调试与读取厂商扩展 PID；非十六进制输入直接拒绝。
  Future<String> sendRaw(String cmd) async {
    if (!_connected) return '未连接：请先连接 OBD 适配器';
    final c = cmd.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (c.isEmpty) return '命令为空';
    if (!RegExp(r'^[0-9A-F]{2,32}$').hasMatch(c)) {
      return '只接受十六进制命令（例：010C / 0902 / 2200）';
    }
    final r = await _sendCmd(c,
        expectMarker: _responseMarker(c),
        timeoutMs: c.startsWith('09') ? 3000 : 1200);
    final text = r.text.trim();
    if (text.isNotEmpty && text.contains('7F')) return text; // 否定应答原样返回
    if (r.timedOut && text.isEmpty) return '超时：ECU 无应答（该 PID 可能不支持）';
    return text.isEmpty ? '空响应' : text;
  }

  /// 读取车架号（Mode 09 PID 02）。
  ///
  /// VIN 是 ISO-TP 多帧响应，`ATCAF0` 下 ELM 只回第一帧（7 字节），拿不全。
  /// 这里临时打开自动格式化（CAF1）让适配器自行重组，读完立刻恢复 CAF0，
  /// 否则后续轮询的紧凑帧解析会全部错位。失败（老车不支持 0902）返回 null。
  Future<VinInfo?> readVin() async {
    if (!_connected) return null;
    try {
      await _sendCmd('ATCAF1', expectMarker: 'OK', timeoutMs: 800);
      await _sendCmd('ATH0', expectMarker: 'OK', timeoutMs: 600);
      var best = await _sendCmd('0902', expectMarker: '49', timeoutMs: 3000);
      var info = VinInfo.parse(best.text);
      if (info == null) {
        // 有的适配器 CAF1 下只回一行，重试一次（ECU 首帧偶尔丢）。
        best = await _sendCmd('0902', expectMarker: '49', timeoutMs: 3000);
        info = VinInfo.parse(best.text);
      }
      return info;
    } catch (_) {
      return null;
    } finally {
      await _sendCmd('ATCAF0', expectMarker: 'OK', timeoutMs: 800);
      await _sendCmd('ATH0', expectMarker: 'OK', timeoutMs: 400);
    }
  }

  /// 请求 → 正响应标记（CAF0/ATH0 紧凑帧下首字节即模式 + 0x40）。
  static String? _responseMarker(String cmd) {
    if (cmd.startsWith('AT')) return 'OK';
    final mode = int.tryParse(cmd.substring(0, 2), radix: 16);
    if (mode == null) return null;
    switch (mode) {
      case 0x01:
        return '41';
      case 0x02:
        return '42';
      case 0x03:
        return '43';
      case 0x04:
        return '44';
      case 0x09:
        return '49';
      case 0x21:
        return '61';
      case 0x22:
        return '62';
      default:
        return null;
    }
  }

  /// Mode 22（UDS ReadDataByIdentifier）支持位图探测的基址：
  /// 22 00 / 22 20 / … / 22 E0，每组回 4 字节掩码。
  static const List<int> mode22Bases = [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0];

  /// 探测本车 ECU 实际支持的 Mode 22 扩展 PID。
  ///
  /// FORScan 的马自达 PID 表未公开，不能凭空写死地址；正确做法是问 ECU
  /// “你支持哪些” —— 未支持组返回 NO DATA / 7F 22 31，支持组回 62 XX + 掩码。
  Future<Mode22Result> probeMode22({void Function(int base)? onProgress}) async {
    if (!_connected) {
      return const Mode22Result(supported: {}, raw: {}, error: 'OBD 未连接');
    }
    final supported = <int>{};
    final raw = <int, String>{};
    var responded = 0;
    for (final base in mode22Bases) {
      onProgress?.call(base);
      final hex = base.toRadixString(16).padLeft(2, '0').toUpperCase();
      final r = await _sendCmd('22$hex', expectMarker: '62', timeoutMs: 1000);
      raw[base] = r.hasData ? r.text : '';
      final mask = parseMode22Mask(base, r.text);
      if (mask.isEmpty) continue;
      responded++;
      supported.addAll(mask);
    }
    _log('Mode 22 探测：${responded} 组应答，支持 ${supported.length} 个扩展 PID');
    return Mode22Result(
      supported: supported,
      raw: raw,
      respondedRanges: responded,
    );
  }

  /// 解析一组 `22 XX` 应答里的 4 字节支持位图（UDS 惯例：首字节最高位 = XX+1）。
  /// 无正响应 / 否定响应 / 长度不足时返回空集。
  static Set<int> parseMode22Mask(int base, String raw) {
    final out = <int>{};
    final s = _cleanHex(raw);
    final hex = base.toRadixString(16).padLeft(2, '0').toUpperCase();
    final idx = s.indexOf('62$hex');
    if (idx < 0) return out;
    final start = idx + 4;
    if (start + 8 > s.length) return out;
    for (var bit = 0; bit < 32; bit++) {
      final off = start + (bit ~/ 8) * 2;
      final b = int.tryParse(s.substring(off, off + 2), radix: 16);
      if (b == null) return out;
      if ((b >> (7 - bit % 8)) & 1 == 1) {
        final pid = base + bit + 1;
        if (pid <= 0xFF) out.add(pid); // 掩码只覆盖低字节 DID
      }
    }
    return out;
  }

  static String _cleanHex(String raw) {
    var s = raw.toUpperCase();
    for (final n in ['SEARCHING...', 'SEARCHING', 'NO DATA', 'STOPPED', '>', '?']) {
      s = s.replaceAll(n, '');
    }
    return s.replaceAll(RegExp(r'[\s\r\n]'), '');
  }

  /// 行流回调（BLE/USB 共用同一套组帧）。
  void _onLine(String line) {
    final c = _pending;
    if (c == null || c.isCompleted) return; // 无在途命令：丢弃杂散行
    _pendingBuf.add(line);
    final joined = _pendingBuf.join('');
    final expect = _pendingExpect;
    if (expect == null) {
      // AT 初始化等：首行即算响应
      _finishPending(timedOut: false);
    } else if (joined.contains(expect)) {
      // 命中预期标记（如 410C / OK）→ 响应驱动立即完成
      _finishPending(timedOut: false);
    }
    // 否则继续缓冲多帧，等超时或下一帧命中。
  }

  void _finishPending({required bool timedOut}) {
    final c = _pending;
    if (c == null || c.isCompleted) return;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    final elapsed = _sw?.elapsedMilliseconds ?? 0;
    _sw?.stop();
    // 更新 RTT EMA（超时也按本次耗时记，便于把超时往上抬一次后再回落）。
    _rttMs = _rttMs * 0.7 + elapsed * 0.3;
    if (timedOut) {
      _consecutiveTimeouts++;
    } else {
      _consecutiveTimeouts = 0;
    }
    final text = _pendingBuf.join('');
    _pendingBuf.clear();
    c.complete(_CmdResult(text: text, timedOut: timedOut));
  }

  void _cancelPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    final c = _pending;
    if (c != null && !c.isCompleted) {
      c.complete(const _CmdResult(text: '', timedOut: true));
    }
    _pending = null;
    _pendingBuf.clear();
  }

  void _startPolling() {
    _running = true;
    _pollLoop();
  }

  Future<void> _pollLoop() async {
    var tick = 0;
    while (_running) {
      if (_batchSupported) {
        // 一次批量请求取全部核心 PID（响应驱动，无固定 sleep）。
        final req = '01${_fastPids.map((p) => p.hex).join()}';
        final r =
            await _sendCmd(req, expectMarker: '41', timeoutMs: _timeoutMs());
        if (r.hasData) {
          PidParser.parseMultiSequential(r.text).forEach(_putValue);
        }
      } else {
        // 单 PID 回退：逐个响应驱动。
        for (final pid in _fastPids) {
          if (!_running) break;
          final r = await _sendCmd(pid.request,
              expectMarker: '41${pid.hex}', timeoutMs: _timeoutMs());
          if (r.hasData) {
            final bytes = PidParser.parseResponse(pid, r.text);
            if (bytes != null) _putValue(pid, pid.decode(bytes));
          }
        }
      }
      // 每 2 轮取一个次要 PID（低频穿插）。
      if (_running && tick % 2 == 0) {
        final pid = _slowPids[_slowIndex % _slowPids.length];
        _slowIndex++;
        final r = await _sendCmd(pid.request,
            expectMarker: '41${pid.hex}', timeoutMs: _timeoutMs());
        if (r.hasData) {
          final bytes = PidParser.parseResponse(pid, r.text);
          if (bytes != null) _putValue(pid, pid.decode(bytes));
        }
      }
      // 推送一帧
      _pushFrame();
      tick++;
      // 响应驱动：核心路径不加固定 60ms sleep，按 ECU 实际往返节奏走。
      // 仅在连续超时（ECU 不在线/点火关闭）时退避，避免空转刷屏。
      if (_consecutiveTimeouts >= 3) {
        await Future.delayed(const Duration(milliseconds: 400));
      } else {
        await Future.delayed(Duration.zero);
      }
    }
  }

  void _pushFrame() {
    final v = _values;
    double get(Pid p) => v[p] ?? 0;
    double? getOrNull(Pid p) => v[p];
    final frame = ObdData(
      connected: true,
      source: 'obd',
      rpm: get(Pid.rpm).round(),
      speed: get(Pid.speed),
      coolant: getOrNull(Pid.coolant),
      oilTemp: getOrNull(Pid.oilTemp),
      intakeTemp: getOrNull(Pid.intakeTemp),
      ambient: getOrNull(Pid.ambient),
      voltage: getOrNull(Pid.voltage),
      map: getOrNull(Pid.map),
      maf: getOrNull(Pid.maf),
      load: getOrNull(Pid.engineLoad),
      absLoad: getOrNull(Pid.absLoad),
      throttle: getOrNull(Pid.throttle),
      fuelLevel: getOrNull(Pid.fuelLevel),
      ltft: getOrNull(Pid.ltft),
      ignAdv: getOrNull(Pid.ignAdv),
      fuelRailP: getOrNull(Pid.fuelRail),
      catTemp: getOrNull(Pid.catTemp),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _telemetry.onRealFrame(frame);
  }

  // ── DTC：读故障码（Mode 03）/ 清故障码（Mode 04） ──

  /// 读取当前 ECU 故障码列表（Mode 03）。未连接返回空。
  Future<List<String>> readDtcs() async {
    if (!_connected) return const [];
    final r = await _sendCmd(DtcCodec.readCommand,
        expectMarker: DtcCodec.positiveMarker, timeoutMs: 1500);
    if (!r.hasData) return const [];
    final codes = DtcCodec.parseMode03(r.text);
    _log('读取 DTC：${codes.isEmpty ? "无码" : codes.join(", ")}');
    return codes;
  }

  /// 清除故障码（Mode 04）：发 "04" → 等 OK → 重读 Mode 03。
  ///
  /// 调用方必须先做用户二次确认（MIL 故障灯熄灭 ≠ 故障修复）。
  /// 仅在 [isConnected] 且非高负荷时调用（本方法不判断车速/转速，由 UI 把关）。
  Future<ClearDtcResult> clearDtcs() async {
    if (!_connected) {
      return const ClearDtcResult(ok: false, error: 'OBD 未连接');
    }
    _log('发起 Mode 04 清除故障码…');
    final r = await _sendCmd(DtcCodec.clearCommand,
        expectMarker: 'OK', timeoutMs: 2000);
    if (!r.hasData) {
      _log('Mode 04 未收到 OK，清除失败');
      return const ClearDtcResult(ok: false, error: 'ECU 未响应清除指令');
    }
    // 等 ECU 落盘（部分车清除后需要几百毫秒再读才准）。
    await Future.delayed(const Duration(milliseconds: 600));
    final after = await readDtcs();
    _log('Mode 04 完成：成功；重读剩余码=${after.isEmpty ? "无" : after.join(",")}');
    return ClearDtcResult(ok: true, aliveCodes: after);
  }

  /// 用户主动断开：停止重连。
  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _running = false;
    _cancelPending();
    await _teardownTransport();
    _connected = false;
    _values.clear();
    _setState(ObdConnStage.disconnected);
  }

  /// 断开并取消订阅 transport（保留对象，不 dispose 以便重连/切换）。
  Future<void> _teardownTransport() async {
    _running = false;
    _cancelPending();
    _lineSub?.cancel();
    _discSub?.cancel();
    _lineSub = null;
    _discSub = null;
    try {
      await _transport?.disconnect();
    } catch (_) {}
  }

  void dispose() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _teardownTransport();
    final t = _transport;
    _transport = null;
    t?.dispose();
    connState.dispose();
  }
}

/// Mode 04 清除故障码结果（顶层类，便于 UI 引用）。
class ClearDtcResult {
  const ClearDtcResult({
    required this.ok,
    this.aliveCodes = const [],
    this.error,
  });

  /// 清除指令是否被 ECU 接受（收到 OK）。
  final bool ok;

  /// 清完后重读 Mode 03 仍存在的码（部分 ECU 在工况不允许时拒绝清除）。
  final List<String> aliveCodes;

  /// 失败原因。
  final String? error;
}

/// Mode 22 扩展 PID 探测结果。
class Mode22Result {
  const Mode22Result({
    required this.supported,
    required this.raw,
    this.respondedRanges = 0,
    this.error,
  });

  /// 本车 ECU 应答支持的 0x22 PID 编号（十进制，如 0x11 = 17）。
  final Set<int> supported;

  /// 每个基址的原始应答，供诊断页显示（排错用）。
  final Map<int, String> raw;

  /// 有正响应的基址组数（0 = ECU 完全不开放扩展数据）。
  final int respondedRanges;

  final String? error;

  bool get isEmpty => supported.isEmpty;

  /// 支持列表，形如 “22 11 · 22 1E · 22 F4”。
  List<String> get labels => (supported.toList()..sort())
      .map((p) => '22 ${p.toRadixString(16).padLeft(2, '0').toUpperCase()}')
      .toList();

  String get summary {
    if (error != null) return error!;
    if (supported.isEmpty) {
      return 'ECU 未开放 Mode 22 扩展数据（$respondedRanges/8 组应答）。'
          '通用 OBD 的转速/车速/水温仍可用，档位继续按齿比反推。';
    }
    return 'ECU 支持 ${supported.length} 个扩展 PID（$respondedRanges/8 组应答）。';
  }
}
