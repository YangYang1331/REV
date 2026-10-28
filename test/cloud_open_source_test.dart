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

    test('checkUpdate 在空端点下直接返回 null（不发请求）', () async {
      final c = CloudService();
      await c.setEndpoint('');
      expect(await c.checkUpdate(39), isNull);
    });
  });
}
