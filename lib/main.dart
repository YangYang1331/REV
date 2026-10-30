import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/splash/splash_screen.dart';
import 'package:obd_dashboard/services/audio_focus_bridge.dart';
import 'package:obd_dashboard/services/alarm_service.dart';
import 'package:obd_dashboard/services/crash_guard.dart';

void main() {
  // 整个启动与运行放在受保护的 zone 里：任何未捕获的异步异常都落盘，
  // 不再直接闪退。
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // 三层崩溃兜底：框架错误 / 平台错误 / 局部 widget 安全占位。
    CrashGuard.install();
    // 报警阈值与语音开关：启动即恢复，行车第一帧就能按用户配置判定。
    AlarmService.instance.restore();
    // 仪表盘横屏优先（全面适配横屏，车机 1280×720/1920×720）+ 常亮。
    // 手机/车机都锁横屏；皮肤不改配色，只确认 orientation 适配。
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.enable();
    // 音频焦点：导航 ducking / 来电暂停 / 挂断恢复，与音乐共存。
    AudioFocusBridge.instance.init();
    runApp(const ProviderScope(child: RevApp()));
  }, (Object error, StackTrace stack) {
    CrashGuard.recordZone(error, stack);
  });
}

class RevApp extends ConsumerWidget {
  const RevApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 启动云端服务（GPS + 3 秒上报）
    ref.read(cloudServiceProvider);
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'REV',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B10),
        colorScheme: base.colorScheme.copyWith(
          primary: const Color(0xFF27D6E6),
          secondary: const Color(0xFF7FF0E6),
          surface: const Color(0xFF0E141B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0x00000000),
          elevation: 0,
          centerTitle: false,
        ),
        textTheme: base.textTheme.apply(
          fontFamily: null,
          bodyColor: const Color(0xFFEAF2F6),
          displayColor: const Color(0xFFEAF2F6),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF27D6E6),
            foregroundColor: const Color(0xFF06121A),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
