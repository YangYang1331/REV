/// 命令串行队列（参考原版 services/command_queue.dart）。
/// ELM327 串口一次只能处理一条命令，必须排队串行发送。
class CommandQueue {
  final List<String> _pending = [];
  bool _sending = false;

  Future<void> Function(String cmd)? _send;
  Future<void> Function(String cmd)? _onResponse;

  void start({
    required Future<void> Function(String cmd) send,
    required Future<void> Function(String cmd) onResponse,
  }) {
    _send = send;
    _onResponse = onResponse;
  }

  void push(String cmd) {
    _pending.add(cmd);
    _drain();
  }

  Future<void> _drain() async {
    if (_sending) return;
    _sending = true;
    while (_pending.isNotEmpty) {
      final cmd = _pending.removeAt(0);
      await _send?.call(cmd);
      await _onResponse?.call(cmd);
    }
    _sending = false;
  }

  void clear() => _pending.clear();
}
