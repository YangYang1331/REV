import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_advice.dart';
import 'package:obd_dashboard/core/obd/obd_pid.dart';
import 'package:obd_dashboard/core/obd/pid_sanity.dart';
import 'package:obd_dashboard/core/store/app_store.dart';

void main() {
  group('v2.16.0 新增机油温度 PID', () {
    test('0x5C 请求字与解码（单字节 -40 偏移）', () {
      expect(Pid.oilTemp.hex, '5C');
      expect(Pid.oilTemp.request, '015C');
      expect(Pid.oilTemp.decode([0x64]), 60); // 100 - 40
    });

    test('单 PID 响应解析', () {
      final bytes = PidParser.parseResponse(Pid.oilTemp, '415C64\r\r>');
      expect(bytes, [0x64]);
      expect(Pid.oilTemp.decode(bytes!), 60);
    });

    test('批量顺序解析可识别 5C', () {
      // 41 | 0C 1AF8 | 5C 78
      final m = PidParser.parseMultiSequential('410C1AF85C78');
      expect(m[Pid.rpm], 1726);
      expect(m[Pid.oilTemp], 80);
    });

    test('合理性校验：0℃~150℃ 内放行，跳变过大拒绝', () {
      expect(PidSanity.isPhysicallyPlausible(Pid.oilTemp, 95), isTrue);
      expect(PidSanity.isPhysicallyPlausible(Pid.oilTemp, 180), isFalse);
      expect(PidSanity.accept(Pid.oilTemp, 90, 92), isTrue);
      expect(PidSanity.accept(Pid.oilTemp, 90, 140), isFalse);
    });
  });

  group('驾驶评分', () {
    test('里程/时长不足不给分', () {
      const t = TripRec(ts: 0, km: 0.2, fuel: 0.02, sec: 60);
      expect(t.score, isNull);
      expect(t.scoreLabel, '--');
    });

    test('平稳行程接近满分', () {
      const t = TripRec(ts: 0, km: 12, fuel: 1.0, sec: 900, maxSpeed: 80);
      expect(t.score, 100);
      expect(t.scoreLabel, '优秀');
    });

    test('急加速/急刹/怠速/超速按权重扣分', () {
      const t = TripRec(
        ts: 0,
        km: 10,
        fuel: 1.0,
        sec: 1000,
        harshAccel: 3,
        harshBrake: 2,
        idleSec: 600, // 60% 怠速 → 扣 12
        violations: 4,
      );
      // 100 - 9 - 8 - 12 - 8 = 63
      expect(t.score, 63);
      expect(t.scoreLabel, '一般');
    });

    test('扣到负数时夹到 0', () {
      const t = TripRec(
          ts: 0, km: 5, fuel: 1, sec: 600, harshBrake: 30, violations: 30);
      expect(t.score, 0);
      expect(t.scoreLabel, '偏激烈');
    });

    test('序列化往返保留轨迹与质量字段', () {
      const t = TripRec(
        ts: 1700000000000,
        km: 8.5,
        fuel: 0.7,
        sec: 720,
        maxSpeed: 112,
        harshAccel: 2,
        harshBrake: 1,
        idleSec: 120,
        violations: 1,
        track: [
          [31.2, 121.5, 60.0],
          [31.21, 121.51, 72.0],
        ],
      );
      final back = TripRec.fromJson(t.toJson());
      expect(back.km, 8.5);
      expect(back.maxSpeed, 112);
      expect(back.track.length, 2);
      expect(back.track[1][2], 72);
    });
  });

  group('故障码维修建议', () {
    test('已知码：失火判为严重且不建议继续开', () {
      final a = DtcAdvice.of('P0300');
      expect(a.severity, 2);
      expect(a.canDrive, contains('不建议'));
      expect(a.selfCheck.length, greaterThanOrEqualTo(3));
    });

    test('未知码按域兜底，永远有建议', () {
      final a = DtcAdvice.of('P2A00');
      expect(a.severity, inInclusiveRange(0, 2));
      expect(a.selfCheck, isNotEmpty);
      expect(a.cost, isNotEmpty);
    });
  });

  group('保养提醒估算', () {
    test('按锚点累加，未填锚点不猜', () {
      const s = MaintState();
      expect(s.currentOdoKm, isNull);
      const t = MaintState(
          accumKm: 1000,
          odoAnchorKm: 50000,
          odoAnchorAccumKm: 1000,
          lastOilOdoKm: 49500);
      expect(t.currentOdoKm, 50000);
      expect(t.sinceOilKm, 500);
    });

    test('累计里程增长后保养差值同步增长', () {
      const s = MaintState(
          accumKm: 1500,
          odoAnchorKm: 50000,
          odoAnchorAccumKm: 1000,
          lastOilOdoKm: 49500);
      expect(s.currentOdoKm, 50500);
      expect(s.sinceOilKm, 1000);
    });
  });
}
