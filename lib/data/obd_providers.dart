import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/services/auth_service.dart';
import 'package:obd_dashboard/services/cloud_service.dart';
import 'package:obd_dashboard/services/obd_service.dart';
import 'package:obd_dashboard/services/sound_service.dart';
import 'package:obd_dashboard/services/tts_service.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';

/// 全局遥测服务（演示 / 真实统一入口）。
final telemetryProvider = ChangeNotifierProvider<TelemetryService>((ref) {
  final s = TelemetryService();
  s.init();
  // 数据丢失心跳：真实模式 1s 检查一次
  final t = Timer.periodic(const Duration(seconds: 1), (_) => s.checkStale());
  ref.onDispose(t.cancel);
  ref.onDispose(s.dispose);
  return s;
});

/// 账号体系（登录 / 注册 / 退出 / 启动恢复）。
final authProvider = ChangeNotifierProvider<AuthService>((ref) {
  final a = AuthService();
  a.restore();
  return a;
});

/// 全局 OBD 服务（BLE ELM327 连接 + PID 轮询）。
/// 必须 read 不能 watch：telemetry 每帧 notify，watch 会让 BLE 服务反复创建销毁。
final obdServiceProvider = Provider<ObdService>((ref) {
  final s = ObdService(ref.read(telemetryProvider));
  ref.onDispose(s.dispose);
  return s;
});

/// 全局云端服务（数据上报 + GPS + 更新）。
final cloudServiceProvider = Provider<CloudService>((ref) {
  final cloud = CloudService();
  // 关键：必须用 read 不能 watch。telemetry 在演示/实车模式下每帧都 notify，
  // 若用 watch 会导致 CloudService 被高频重建，3 秒上报定时器刚创建就被
  // onDispose 取消，永远发不出一帧。read 只取单例，其字段在定时器里实时读取。
  final tele = ref.read(telemetryProvider);
  // 同理 auth 也用 read：登录/退出时其字段原地更新，定时器读取即为最新态。
  final auth = ref.read(authProvider);
  SoundService.instance.init();
  // 初始化 TTS（Trigger 语音播报用；无引擎设备自动跳过，不影响主流程）。
  TtsService.instance.init();

  cloud.init().then((_) async {
    cloud.startGps();
    // 启动恢复登录态并补传离线帧
    await auth.restore();
    if (auth.isLoggedIn) {
      await cloud.flushQueue(token: auth.token);
    }
    // 每 3 秒上报一帧：必须已登录且真实 OBD 连接活跃时才上报（连上才跳数据、断开自动离线）；
    // 演示模式不上报，避免假数据污染看板（调试可在设置里手动开启演示上报）。
    final t = Timer.periodic(const Duration(seconds: 3), (_) {
      if (tele.shouldReportToCloud && auth.isLoggedIn) {
        cloud.report(tele.current, token: auth.token);
      }
    });
    ref.onDispose(t.cancel);
  });
  return cloud;
});

/// 兼容性别名。
final appDataSourceProvider = telemetryProvider;
