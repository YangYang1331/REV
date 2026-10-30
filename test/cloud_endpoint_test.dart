// 上报地址规范化 / 404 自愈单元测试。
// 背景：用户把云服务器地址填成 http://139.224.30.235/c/api/v1/report，
// 上报一直 404，看板永远 NO SIGNAL。
import 'package:flutter_test/flutter_test.dart';

import 'package:obd_dashboard/services/cloud_service.dart';

void main() {
  group('normalizeEndpoint', () {
    test('只有主机：补协议 + 补标准上报路径', () {
      expect(CloudService.normalizeEndpoint('139.224.30.235'),
          'http://139.224.30.235/api/v1/report');
      expect(CloudService.normalizeEndpoint('  mayangyang.eu.cc/  '),
          'https://mayangyang.eu.cc/api/v1/report');
    });

    test('裸域名默认 HTTPS；裸公网 IP / 内网地址保持 HTTP', () {
      // 域名有证书可走（Let's Encrypt 等），优先加密。
      expect(CloudService.normalizeEndpoint('car.example.com'),
          'https://car.example.com/api/v1/report');
      // 公网 IP 通常没有证书，硬升 https 会直接连不上。
      expect(CloudService.normalizeEndpoint('8.8.8.8:8080'),
          'http://8.8.8.8:8080/api/v1/report');
      for (final h in ['192.168.1.9', '10.0.0.5', 'localhost', 'rev.lan']) {
        expect(CloudService.normalizeEndpoint('$h:8080/api/v1/report'),
            startsWith('http://'));
      }
    });

    test('显式 http + 域名 → 自动升级 https（仅域名，不动 IP/内网）', () {
      expect(CloudService.normalizeEndpoint('http://car.example.com/api/v1/report'),
          'https://car.example.com/api/v1/report');
      expect(CloudService.normalizeEndpoint('http://139.224.30.235/api/v1/report'),
          'http://139.224.30.235/api/v1/report');
      expect(CloudService.normalizeEndpoint('http://192.168.0.10:8080/api/v1/report'),
          'http://192.168.0.10:8080/api/v1/report');
    });

    test('带多余路径前缀也会补上 /api/v1/report', () {
      // 用户截图里的写法：/c 结尾（少了后面的路径）
      expect(CloudService.normalizeEndpoint('http://139.224.30.235/c'),
          'http://139.224.30.235/c/api/v1/report');
    });

    test('已经是规范地址则原样保留（幂等）', () {
      const good = 'http://139.224.30.235/api/v1/report';
      expect(CloudService.normalizeEndpoint(good), good);
      expect(CloudService.normalizeEndpoint('$good/'), good);
      expect(CloudService.normalizeEndpoint(CloudService.normalizeEndpoint(good)),
          good);
    });

    test('https + 端口 + 自建子路径前缀不被吃掉', () {
      expect(CloudService.normalizeEndpoint('https://car.example.com:8443/rev'),
          'https://car.example.com:8443/rev/api/v1/report');
      expect(CloudService.normalizeEndpoint('https://car.example.com/rev/api/v1/report'),
          'https://car.example.com/rev/api/v1/report');
    });

    test('空串保持空串（开源版不上报）', () {
      expect(CloudService.normalizeEndpoint('   '), '');
    });
  });

  group('canonicalReportUrl（404 自愈目标）', () {
    test('多写了 /c 的地址给出同主机规范地址', () {
      expect(
        CloudService.canonicalReportUrl('http://139.224.30.235/c/api/v1/report'),
        'http://139.224.30.235/api/v1/report',
      );
    });

    test('已规范 / 非法地址返回 null（不重复发送）', () {
      expect(
        CloudService.canonicalReportUrl('http://139.224.30.235/api/v1/report'),
        isNull,
      );
      expect(CloudService.canonicalReportUrl('not a url'), isNull);
    });

    test('保留协议与端口，只替换路径', () {
      expect(
        CloudService.canonicalReportUrl('https://car.example.com:8443/rev/report'),
        'https://car.example.com:8443/api/v1/report',
      );
    });
  });
}
