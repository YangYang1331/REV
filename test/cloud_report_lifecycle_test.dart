// 回归：演示模式下 telemetry 每帧高频 notify，云端上报定时器不能被取消，
// 登录后必须真正把 demo 帧 POST 到服务器（修复 cloudServiceProvider 误 watch
// telemetry 导致 Provider 高频重建、3 秒定时器反复创建即取消的 bug）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/services/auth_service.dart';

/// 覆盖 flutter_test 默认的 400 拦截，走真实 HttpClient（连本地 socket）。
class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

class _MockServer {
  HttpServer? _server;
  int reportCount = 0;
  int loginCount = 0;
  final List<String> reportBodies = [];

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      if (req.uri.path.endsWith('/api/v1/report')) {
        reportCount++;
        reportBodies.add(body);
      } else if (req.uri.path.endsWith('/api/auth/login') ||
          req.uri.path.endsWith('/api/auth/register')) {
        loginCount++;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.statusCode = 200;
      req.response.write(jsonEncode({
        'ok': true,
        'token': 'mock-token-123456',
        'username': 'u',
        'role': 'user',
      }));
      await req.response.close();
    });
    return _server!.port;
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _RealHttpOverrides();
    // geolocator 平台通道在单测里不存在：让 startGps 判定为定位服务关闭，直接 return false，
    // 不抛 MissingPluginException（不影响上报定时器）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => false,
    );
    // audioplayers 插件通道：所有调用静默成功，避免 SoundService 单例初始化抛插件异常。
    for (final ch in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  test('demo 高频刷新时上报定时器存活并发出 demo 帧', () async {
    final mock = _MockServer();
    final port = await mock.start();
    final base = 'http://127.0.0.1:$port';

    SharedPreferences.setMockInitialValues({
      // 云端上报地址指向本地 mock
      'cloud_endpoint': '$base/api/v1/report',
    });

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) {
        final a = AuthService(baseUrl: base);
        a.restore();
        return a;
      }),
    ]);
    addTearDown(container.dispose);

    // 启动 telemetry（demo 模式会持续产生帧并 notify）
    final tele = container.read(telemetryProvider);
    await Future<void>.delayed(const Duration(seconds: 2));

    // 登录
    final auth = container.read(authProvider);
    final r = await auth.login('u', 'p');
    expect(r.ok, isTrue, reason: 'mock 登录应成功: ${r.error}');
    expect(auth.isLoggedIn, isTrue);

    // 启动云端服务（3 秒上报定时器）
    container.read(cloudServiceProvider);

    // demo 持续高频刷新 8 秒：3 秒定时器应至少 tick 2 次，
    // 若 Provider 被高频重建，定时器会被反复 cancel，reportCount 会是 0。
    await Future<void>.delayed(const Duration(seconds: 8));

    expect(tele.shouldReportToCloud, isTrue,
        reason: 'demo 模式 + 开关默认开应允许上报');
    expect(tele.current.source, 'demo');
    expect(tele.current.speed, greaterThanOrEqualTo(0));
    expect(mock.reportCount, greaterThanOrEqualTo(1),
        reason: '8 秒内应至少收到 1 帧上报；实际 ${mock.reportCount}');
    // 上报的是 demo 源
    expect(mock.reportBodies.first, contains('"source":"demo"'));

    await mock.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));
}
