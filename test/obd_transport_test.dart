// B 线（连接层）测试：
//  1) ObdTransport 抽象 + 共享 LineFramer 组帧（BLE/USB 同一路径）；
//  2) BLE/USB 共用的 OBD 解码：核心 PID 公式、多 PID 批量切分、噪声/超时帧容错；
//  3) FakeTransport 回放 ELM 文本，驱动 ObdService 走到 polling 并产出真实帧。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obd_dashboard/core/obd/obd_pid.dart';
import 'package:obd_dashboard/services/obd_service.dart';
import 'package:obd_dashboard/services/obd_transport.dart';
import 'package:obd_dashboard/services/telemetry_service.dart';

/// 假传输层：按脚本顺序回放 ELM 响应行（onLine 已清洗，等价于 BLE/USB 组帧后的输出）。
class FakeTransport implements ObdTransport {
  FakeTransport(this.script);

  /// 每次 writeString 按序吐一行。
  final List<String> script;
  int _idx = 0;
  final _lineCtrl = StreamController<String>.broadcast();
  final _discCtrl = StreamController<void>.broadcast();
  bool _connected = false;

  @override
  String get displayName => 'Fake';

  @override
  String? get storageId => null;

  @override
  String? get storageLabel => null;

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get onLine => _lineCtrl.stream;

  @override
  Stream<void> get onDisconnected => _discCtrl.stream;

  @override
  Future<bool> connect() async {
    _connected = true;
    return true;
  }

  @override
  Future<void> writeString(String s) async {
    if (_idx < script.length) {
      final resp = script[_idx++];
      scheduleMicrotask(() => _lineCtrl.add(resp));
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  void dispose() {
    _lineCtrl.close();
    _discCtrl.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // audioplayers 通道静默（SoundService.playConnected 在 try/catch 里，这里双保险）。
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  group('LineFramer 组帧（BLE/USB 共用）', () {
    test('按 \\r \\n > 切行，trim + 大写', () {
      final out = <String>[];
      final f = LineFramer(onLine: out.add);
      f.addText('41 0C 1F 88\r>410D3C\r\n>OK>');
      expect(out, ['410C1F88', '410D3C', 'OK']);
    });

    test('粘包 / 分包：多次喂字节，残留缓冲正确', () {
      final out = <String>[];
      final f = LineFramer(onLine: out.add);
      f.addBytes('410'.codeUnits);
      f.addBytes('C1F'.codeUnits);
      f.addBytes('88\r'.codeUnits);
      f.addText('>');
      expect(out, ['410C1F88']);
    });

    test('空行 / 纯提示符不产生行', () {
      final out = <String>[];
      final f = LineFramer(onLine: out.add);
      f.addText('\r\n>\r\n');
      expect(out, isEmpty);
    });
  });

  group('核心 PID 解码公式（马6 ISO15765-4）', () {
    test('010C 转速 = (A*256+B)/4', () {
      // "41 0C 1F 88" -> A=0x1F B=0x88 -> (31*256+136)/4 = 2018
      final bytes = PidParser.parseResponse(Pid.rpm, '41 0C 1F 88');
      expect(bytes, isNotNull);
      expect(Pid.rpm.decode(bytes!), closeTo(2018, 0.01));
    });

    test('010D 车速 = A km/h', () {
      final bytes = PidParser.parseResponse(Pid.speed, '41 0D 3C');
      expect(Pid.speed.decode(bytes!), closeTo(60, 0.01));
    });

    test('0105 水温 = A-40 ℃', () {
      final bytes = PidParser.parseResponse(Pid.coolant, '41 05 50');
      // 0x50=80 -> 40℃
      expect(Pid.coolant.decode(bytes!), closeTo(40, 0.01));
    });

    test('0111 油门 = A*100/255 %', () {
      final bytes = PidParser.parseResponse(Pid.throttle, '41 11 20');
      expect(Pid.throttle.decode(bytes!), closeTo(32 * 100 / 255, 0.01));
    });

    test('0104 发动机负荷 = A*100/255 %', () {
      final bytes = PidParser.parseResponse(Pid.engineLoad, '41 04 32');
      expect(Pid.engineLoad.decode(bytes!), closeTo(50 * 100 / 255, 0.01));
    });
  });

  group('多 PID 批量响应切分', () {
    test('批量请求 010C0D051104 的紧凑响应能切到各 PID', () {
      // 正响应: 41 | 0C 1F 88 | 0D 3C | 05 50 | 11 20 | 04 32
      const raw = '410C1F880D3C055011200432';
      final m = PidParser.parseMultiSequential(raw);
      expect(m[Pid.rpm], closeTo(2018, 0.01));
      expect(m[Pid.speed], closeTo(60, 0.01));
      expect(m[Pid.coolant], closeTo(40, 0.01));
      expect(m[Pid.throttle], isNotNull);
      expect(m[Pid.engineLoad], isNotNull);
    });

    test('带空格与提示符的批量行也能解析', () {
      const raw = '41 0C 1F 88 0D 3C 05 50 11 20 04 32>';
      final m = PidParser.parseMultiSequential(raw);
      expect(m[Pid.rpm], closeTo(2018, 0.01));
      expect(m[Pid.speed], closeTo(60, 0.01));
    });
  });

  group('非法 / 超时帧容错（不崩、丢弃）', () {
    test('SEARCHING... / NO DATA / ? 返回 null 或空', () {
      expect(PidParser.parseResponse(Pid.rpm, 'SEARCHING...'), isNull);
      expect(PidParser.parseResponse(Pid.rpm, 'NO DATA'), isNull);
      expect(PidParser.parseResponse(Pid.rpm, '?'), isNull);
      expect(PidParser.parseMultiSequential('NO DATA'), isEmpty);
      expect(PidParser.parseMultiSequential('SEARCHING...'), isEmpty);
    });

    test('缺字节段 / 乱码不抛异常', () {
      expect(() => PidParser.parseResponse(Pid.rpm, '410C'), returnsNormally);
      expect(PidParser.parseResponse(Pid.rpm, '410C'), isNull);
      expect(() => PidParser.parseMultiSequential('410C1F'), returnsNormally);
      expect(PidParser.parseMultiSequential('GARBAGE'), isEmpty);
      expect(PidParser.parseMultiSequential(''), isEmpty);
    });
  });

  group('ObdService 端到端（FakeTransport 回放）', () {
    test('连接 → ELM 初始化 → 批量探测 → polling 产出真实帧', () async {
      final tele = TelemetryService();
      final svc = ObdService(tele);

      // 脚本：ATZ 回 ELM327；基础 AT 命令回 OK；ATSP0 回 OK；0100 回位图；
      //       ATDPN 回 A6（CAN 11bit 自动选中）；ATST20/ATCAF0 回 OK；
      //       之后每次批量请求回同一帧。
      const batch = '410C1F880D3C055011200432';
      final script = <String>[
        'ELM327', // ATZ
        'OK', // ATE0
        'OK', // ATL0
        'OK', // ATS0
        'OK', // ATH0
        'OK', // ATSP0
        '4100', // 0100 位图（触发协议协商）
        'A6', // ATDPN → CAN 11bit 500k 自动选中
        'OK', // ATST20
        'OK', // ATCAF0
        batch, // 批量探测
        batch, // 轮询 1
        batch, // 轮询 2
        batch, // 轮询 3
      ];
      final t = FakeTransport(script);

      final ok = await svc.connect(t);
      expect(ok, isTrue);
      expect(svc.isConnected, isTrue);

      // 等待轮询推入几帧
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // telemetry 拿到真实转速（≈2018）
      expect(tele.current.source, 'obd');
      expect(tele.current.rpm, closeTo(2018, 2));
      expect(tele.current.speed, closeTo(60, 0.1));

      await svc.disconnect();
      svc.dispose();
    });
  });
}
