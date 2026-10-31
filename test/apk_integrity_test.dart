// v2.17.4 安全加固：更新包 SHA-256 校验 + 公网明文地址拒绝。
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'package:obd_dashboard/services/cloud_service.dart';

void main() {
  test('sha256OfFile 与一次性摘要一致', () async {
    final dir = await Directory.systemTemp.createTemp('rev_sha');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File('${dir.path}/payload.bin');
    final bytes = List<int>.generate(5000, (i) => i % 251);
    await file.writeAsBytes(bytes);

    expect(await CloudService.sha256OfFile(file),
        crypto.sha256.convert(bytes).toString());
  });

  test('公网 http 更新地址直接拒绝', () async {
    final cloud = CloudService();
    addTearDown(cloud.dispose);
    await expectLater(
      cloud.downloadAndInstall('http://8.8.8.8/rev-latest.apk'),
      throwsA(isA<StateError>()),
    );
  });
}
