/// 行程 coast 状态机（纯 Dart、无平台依赖，可注入时钟，便于单测）。
///
/// 在「逐帧语义判断」层面，把原来笼统的「2s 归零 / 6s 熄火」细化成四种情况：
///  - **行驶中**（车速超过移动阈值）：静默，不切段、不打扰；
///  - **红灯 / 滑行停车**（车速≈0，但转速仍在怠速带）：行程继续，停车等待不计异常；
///  - **真熄火**（转速也长期≈0，超过确认时长）：落盘并结束当前行程；
///  - **熄火后又检测到移动 / 转速恢复**：自动开一个新行程段。
///
/// 用法：每收到一帧车辆数据，就喂一次 [update]；根据返回的 [CoastEvent]
/// 决定是否落盘结束行程、或开一个新行程段。状态机本身不碰存储、不发通知。
enum CoastState {
  /// 行驶中（或起步后）。
  driving,

  /// 已停稳但发动机仍在怠速（红灯 / 滑行等待）。行程保持开启。
  parked,

  /// 发动机已熄火（或长时间无帧视为离车）。行程已落盘。
  off,
}

/// 本次喂帧产生的动作。
enum CoastEvent {
  /// 无动作（继续开 / 停车等待中）。
  none,

  /// 真熄火确认：应把当前行程落盘并结束。
  endTrip,

  /// 熄火后又动起来 / 转速恢复：应开一个新的行程段（累加器清零重启）。
  beginNewTrip,
}

class CoastStateMachine {
  CoastStateMachine({
    required this.idleRpm,
    this.movingSpeedKmh = 3.0,
    this.offRpmFactor = 0.4, // rpm < idleRpm*factor 视为发动机已熄火
    this.idleRpmLowFactor = 0.6,
    this.idleRpmHighFactor = 1.6,
    this.offConfirmMs = 5000,
    this.resumeSpeedKmh = 5.0,
  });

  /// 发动机怠速转速（来自车型档案）。
  final double idleRpm;

  /// 车速 > 此值视为在移动。
  final double movingSpeedKmh;

  /// 转速低于怠速 × 此系数 = 发动机已熄火（无转速信号）。
  final double offRpmFactor;

  /// 怠速带下界（怠速 × 系数）：转速高于它才算发动机活着。
  final double idleRpmLowFactor;

  /// 怠速带上界（怠速 × 系数）：转速高于它视为带载行驶而非原地怠速。
  final double idleRpmHighFactor;

  /// 转速持续低于熄火阈值多久才确认「真熄火」。
  final int offConfirmMs;

  /// 熄火后车速超过此值，或转速恢复，视为重新出发。
  final double resumeSpeedKmh;

  CoastState _state = CoastState.driving;

  /// 进入「转速≈0」的起始时间（ms）；null 表示当前不在熄火计数中。
  int? _offSinceMs;

  CoastState get state => _state;

  double get _offRpm => idleRpm * offRpmFactor;
  double get _idleLow => idleRpm * idleRpmLowFactor;
  double get _idleHigh => idleRpm * idleRpmHighFactor;

  /// 喂入一帧 (speedKmh, rpm, nowMs)，返回本次应执行的动作。
  CoastEvent update(double speedKmh, double rpm, int nowMs) {
    final moving = speedKmh > movingSpeedKmh;
    final engineOff = rpm < _offRpm;

    switch (_state) {
      case CoastState.driving:
        if (moving) {
          _offSinceMs = null;
          return CoastEvent.none; // 行驶静默
        }
        if (engineOff) {
          _offSinceMs ??= nowMs;
          if (nowMs - _offSinceMs! >= offConfirmMs) {
            _state = CoastState.off;
            _offSinceMs = null;
            return CoastEvent.endTrip;
          }
          return CoastEvent.none;
        }
        // idling → 红灯停车：行程继续，不切段。
        _offSinceMs = null;
        return CoastEvent.none;

      case CoastState.parked:
        if (moving || rpm >= _idleHigh) {
          // 起步 / 带载行驶：行程继续（不另开新段）。
          _state = CoastState.driving;
          _offSinceMs = null;
          return CoastEvent.none;
        }
        if (engineOff) {
          _offSinceMs ??= nowMs;
          if (nowMs - _offSinceMs! >= offConfirmMs) {
            _state = CoastState.off;
            _offSinceMs = null;
            return CoastEvent.endTrip;
          }
          return CoastEvent.none;
        }
        // 仍在原地怠速等待：什么都不做。
        return CoastEvent.none;

      case CoastState.off:
        // 熄火后：检测到移动 或 转速恢复（回到怠速带）→ 新行程段。
        if (speedKmh > resumeSpeedKmh || rpm > _idleLow) {
          _state = CoastState.driving;
          _offSinceMs = null;
          return CoastEvent.beginNewTrip;
        }
        return CoastEvent.none;
    }
  }
}
