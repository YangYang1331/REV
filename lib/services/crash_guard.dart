import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局崩溃兜底。
///
/// 覆盖三层：
///  1. Flutter 框架内（build / layout / paint / 手势）错误 →
///     [FlutterError.onError]，落盘日志。
///  2. 平台通道 / 引擎层错误（含未 await 的 Future）→
///     [PlatformDispatcher.onError]，返回 true 标记已处理。
///  3. runApp 之外的 zone 异步错误 → runZonedGuarded → [recordZone]。
///
/// 单个 widget 构建失败时用 [ErrorWidget.builder] 给一个安全占位，
/// 避免一个皮肤/页面的局部异常把整个仪表盘打崩（红屏/闪退）。
/// 所有日志落盘均 try/catch，日志失败绝不允许再次抛错。
class CrashGuard {
  static const _kLog = 'rev_crash_log';
  static const _max = 12;

  static void install() {
    // 1. Flutter 框架内错误
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _record(
          'Flutter', details.exceptionAsString(), details.stack?.toString());
    };

    // 2. 平台 / 引擎层错误
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _record('Platform', error.toString(), stack.toString());
      return true;
    };

    // 3. 局部 widget 崩溃 → 安全占位（不红屏、不闪退）
    ErrorWidget.builder = (FlutterErrorDetails details) {
      _record(
          'Widget', details.exceptionAsString(), details.stack?.toString());
      return const _SafeErrorPlaceholder();
    };
  }

  /// 供 runZonedGuarded 调用：捕获 zone 内未处理的异步错误。
  static void recordZone(Object error, StackTrace? stack) {
    _record('Zone', error.toString(), stack?.toString());
  }

  static Future<void> _record(
      String tag, String msg, String? stack) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kLog) ?? <String>[];
      final time = DateTime.now().toIso8601String();
      final tail = stack == null
          ? ''
          : '\n${stack.split('\n').take(8).join('\n')}';
      list.insert(0, '[$time][$tag] $msg$tail');
      if (list.length > _max) list.removeRange(_max, list.length);
      await prefs.setStringList(_kLog, list);
    } catch (_) {
      // 日志记录失败也不允许再抛异常。
    }
  }

  static Future<List<String>> readLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_kLog) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> clearLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLog);
    } catch (_) {}
  }
}

/// 局部 widget 崩溃时的安全占位：保持深色仪表底、不打扰驾驶。
class _SafeErrorPlaceholder extends StatelessWidget {
  const _SafeErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFF070B10),
      child: Center(
        child: Text('···',
            style: TextStyle(
                color: Colors.white24,
                fontSize: 18,
                letterSpacing: 4)),
      ),
    );
  }
}
