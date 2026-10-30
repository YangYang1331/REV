import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obd_dashboard/models/obd_data.dart';
import 'package:obd_dashboard/services/cloud_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  group('服务器地址编译期注入（DEFAULT_BASE/ENDPOINT）', () {
    test('默认（无 dart-define）：内置默认端点为空', () {
      // 普通 `flutter test` 不传 dart-define → 默认值为空。
      expect(CloudService.defaultBase, '');
      expect(CloudService.defaultEndpoint, '');
    });

    test('端点为空时不自动上报、不发请求', () async {
      final c = CloudService();
      await c.setEndpoint('');
      expect(c.endpoint, '');
      expect(c.needsUserServer, isTrue);
      await c.report(const ObdData(
        connected: true,
        source: 'obd',
        rpm: 1000,
        speed: 30,
      ));
      expect(await c.pendingCount(), 0);
    });

    test('checkUpdate 在空端点下抛出「未配置」而不是谎报已是最新', () async {
      final c = CloudService();
      await c.setEndpoint('');
      // v2.17.1：空端点曾经返回 null，界面会显示"已是最新版本"，
      // 用户因此永远升不了级。现在必须明确抛出，由 UI 提示未配置服务器。
      await expectLater(c.checkUpdate(39), throwsA(isA<StateError>()));
    });
  });
}
