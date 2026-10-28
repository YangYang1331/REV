import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/game/game_telemetry.dart';
import 'package:obd_dashboard/core/game/game_udp_parser.dart';

void main() {
  group('GameUdpParser', () {
    test('Forza: 读取 rpm 与速度矢量、挡位', () {
      final bd = ByteData(0x44);
      bd.setFloat32(0x10, 6200, Endian.little); // rpm
      bd.setFloat32(0x20, 10, Endian.little); // vx m/s
      bd.setFloat32(0x24, 0, Endian.little);
      bd.setFloat32(0x28, 0, Endian.little);
      final bytes = bd.buffer.asUint8List();
      bytes[0x43] = 3; // gear
      final t = GameUdpParser.parse(GameProtocol.forza, bytes);
      expect(t, isNotNull);
      expect(t!.rpm, closeTo(6200, 1));
      expect(t.speedKmh, closeTo(36, 0.5)); // 10 m/s = 36 km/h
      expect(t.gear, 3);
    });

    test('Forza: 短包返回 null', () {
      expect(GameUdpParser.parse(GameProtocol.forza, Uint8List(10)), isNull);
    });

    test('F1 CarTelemetry(6): speed u16 @0x18, gear i8 @0x27, rpm u16 @0x28', () {
      final bd = ByteData(0x2C);
      bd.setUint8(0x06, 6); // packetId
      bd.setUint16(0x18, 180, Endian.little); // km/h
      bd.setInt8(0x27, 4); // gear
      bd.setUint16(0x28, 7500, Endian.little); // rpm
      final t = GameUdpParser.parse(GameProtocol.f1, bd.buffer.asUint8List());
      expect(t, isNotNull);
      expect(t!.speedKmh, closeTo(180, 0.1));
      expect(t.gear, 4);
      expect(t.rpm, closeTo(7500, 1));
    });

    test('AC: speed f32 @0x08, rpm f32 @0x0C, gear i32 @0x1C', () {
      final bd = ByteData(0x20);
      bd.setFloat32(0x08, 120.5, Endian.little);
      bd.setFloat32(0x0C, 8000, Endian.little);
      bd.setInt32(0x1C, 6, Endian.little);
      final t =
          GameUdpParser.parse(GameProtocol.assettoCorsa, bd.buffer.asUint8List());
      expect(t!.rpm, closeTo(8000, 1));
      expect(t.speedKmh, closeTo(120.5, 0.1));
      expect(t.gear, 6);
    });

    test('BeamNG: 魔数 GAUG + 偏移', () {
      final bd = ByteData(0x38);
      bd.setUint8(0, 0x47); // G
      bd.setUint8(1, 0x41); // A
      bd.setUint8(2, 0x55); // U
      bd.setUint8(3, 0x47); // G
      bd.setFloat32(0x08, 3000, Endian.little);
      bd.setFloat32(0x10, 50, Endian.little);
      bd.setInt32(0x34, 2, Endian.little);
      final t =
          GameUdpParser.parse(GameProtocol.beamng, bd.buffer.asUint8List());
      expect(t!.rpm, closeTo(3000, 1));
      expect(t.speedKmh, closeTo(50, 0.1));
      expect(t.gear, 2);
    });

    test('BeamNG: 错误魔数返回 null', () {
      final bd = ByteData(0x38);
      bd.setFloat32(0x08, 3000, Endian.little);
      expect(GameUdpParser.parse(GameProtocol.beamng, bd.buffer.asUint8List()),
          isNull);
    });

    test('协议端口注册表', () {
      expect(GameProtocol.forza.port, 5300);
      expect(GameProtocol.f1.port, 20777);
      expect(GameProtocol.assettoCorsa.port, 9996);
      expect(GameProtocol.beamng.port, 4564);
      expect(GameProtocol.ets2.port, 20818);
      expect(GameProtocol.byPort(9996), GameProtocol.assettoCorsa);
    });
  });
}
