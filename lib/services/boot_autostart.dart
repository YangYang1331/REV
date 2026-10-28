import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 开机自启开关（v2.14.0）。
///
/// 开关同时写两份：
///  - Flutter shared_preferences（key `rev_boot_autostart`，原生读取时加
///    `flutter.` 前缀，与 BootReceiver / MainActivity 对齐）；
///  - 原生 `rev/device` 方法通道（保持两边一致，便于设置页实时读写）。
///
/// 默认开。Android 10+ 国产 ROM 常默认禁止自启动，可调用 [openGuide] 跳厂商
/// "自启动管理"页引导用户放行。
class BootAutostart {
  BootAutostart._();
  static final BootAutostart instance = BootAutostart._();

  static const _channel = MethodChannel('rev/device');
  static const _kPref = 'rev_boot_autostart';

  Future<bool> get enabled async {
    try {
      final v = await _channel.invokeMethod<bool>('getBootAutostart');
      if (v != null) return v;
    } catch (e) {
      debugPrint('getBootAutostart native failed, fallback pref: $e');
    }
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_kPref) ?? true; // 默认开
    } catch (_) {
      return true;
    }
  }

  Future<void> setEnabled(bool on) async {
    try {
      await _channel.invokeMethod<void>('setBootAutostart', on);
    } catch (e) {
      debugPrint('setBootAutostart native failed: $e');
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kPref, on);
    } catch (_) {}
  }

  /// 跳厂商"自启动管理"页（小米/华为/OPPO/vivo…），失败则退到应用详情页。
  Future<void> openGuide() async {
    try {
      await _channel.invokeMethod<void>('openBootAutostartSettings');
    } catch (e) {
      debugPrint('openBootAutostartSettings failed: $e');
    }
  }
}
