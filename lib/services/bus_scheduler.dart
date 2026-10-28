/// 总线调度（参考原版 services/bus_scheduler.dart）。
/// 控制 PID 轮询节奏：当总线繁忙时自动降低刷新频率，避免压垮 ELM327。
class BusScheduler {
  BusScheduler({this.baseIntervalMs = 200, this.maxIntervalMs = 800});

  final int baseIntervalMs;
  final int maxIntervalMs;

  int _intervalMs = 200;
  bool _busBusy = false;

  int get intervalMs => _intervalMs;

  /// 收到响应过快/过慢时调用，调整轮询间隔
  void observeRound(bool respondedInTime) {
    if (!respondedInTime) {
      // 响应慢/超时 → 降低频率
      _busBusy = true;
      _intervalMs = (_intervalMs * 2).clamp(baseIntervalMs, maxIntervalMs);
    } else {
      _busBusy = false;
      _intervalMs = baseIntervalMs;
    }
  }

  bool get isBusBusy => _busBusy;
}
