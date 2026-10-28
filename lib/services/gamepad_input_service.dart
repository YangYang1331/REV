import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:obd_dashboard/core/input/gear_shift_map.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';

/// 蓝牙/USB 手柄换挡输入服务。
///
/// 不引入新插件：Flutter 会把 Android 手柄按键以 [KeyEvent] 形式投递，
/// 这里用 [HardwareKeyboard] 全局监听，按物理键的稳定符号映射升/降挡。
/// 支持"按下任意键完成绑定"。GPS / 游戏模式下通过 [TelemetryService.nudgeGear]
/// 手动拨片加减挡。
class GamepadInputService {
  GamepadInputService._();
  static final GamepadInputService instance = GamepadInputService._();

  TelemetryService? _telemetry;
  GearShiftMap _map = GearShiftMap.initial();
  bool _listening = false;

  /// 等待绑定的动作（非空时，下一次按键会绑定到该动作而非换挡）。
  ShiftAction? _bindingPending;
  ShiftAction? get bindingPending => _bindingPending;

  GearShiftMap get map => _map;

  /// 绑定变化通知（UI 刷新）。
  final ValueNotifier<GearShiftMap> notifier =
      ValueNotifier(GearShiftMap.initial());

  Future<void> attach(TelemetryService telemetry) async {
    _telemetry = telemetry;
    final raw = await AppStore.instance.getGearMapJson();
    if (raw != null) {
      try {
        _map = GearShiftMap.fromJson(raw);
      } catch (_) {}
    }
    notifier.value = _map;
    _start();
  }

  void _start() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void dispose() {
    if (!_listening) return;
    _listening = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  /// 把物理键转成稳定符号（usbHidUsage hex，跨设备稳定）。
  String _symbolOf(KeyEvent e) {
    final usage = e.physicalKey.usbHidUsage;
    return 'GameButton${usage.toRadixString(16).toUpperCase()}';
  }

  /// 进入绑定模式：下一次按键绑定到 [action]。
  void startBinding(ShiftAction action) {
    _bindingPending = action;
  }

  void cancelBinding() {
    _bindingPending = null;
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final symbol = _symbolOf(e);

    // 绑定模式：把该键分配给待绑定动作。
    if (_bindingPending != null) {
      _map = _map.rebind(symbol, _bindingPending!);
      _bindingPending = null;
      notifier.value = _map;
      AppStore.instance.setGearMapJson(_map.toJson());
      return true; // 吞掉按键，不触发换挡
    }

    final action = _map.actionFor(symbol);
    if (action == ShiftAction.none) return false;
    final delta = action == ShiftAction.up ? 1 : -1;
    try {
      _telemetry?.nudgeGear(delta);
    } catch (err) {
      debugPrint('shift nudge failed: $err');
    }
    return true;
  }
}
