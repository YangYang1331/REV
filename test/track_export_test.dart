import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/trips/track_export.dart';

TripRec trip({
  int ts = 1700000000000,
  double km = 10,
  double fuel = 0.8,
  double sec = 600,
  double maxSpeed = 80,
  List<List<double>> track = const [],
  String vehicleId = 'v1',
}) =>
    TripRec(
      ts: ts,
      km: km,
      fuel: fuel,
      sec: sec,
      maxSpeed: maxSpeed,
      harshAccel: 2,
      harshBrake: 1,
      idleSec: 60,
      violations: 1,
      vehicleId: vehicleId,
      track: track,
    );

List<List<double>> line([int n = 5]) =>
    [for (var i = 0; i < n; i++) [30.0 + i * 0.001, 120.0 + i * 0.001, 40.0]];

void main() {
  group('GPX / KML 导出', () {
    test('GPX 含全部轨迹点与速度扩展', () {
      final g = TrackExport.gpx(trip(track: line(4)));
      expect(g, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(g, contains('<gpx version="1.1" creator="REV"'));
      expect('<trkpt'.allMatches(g).length, 4);
      expect(g, contains('lat="30.000000"'));
      expect(g, contains('lon="120.003000"'));
      expect(g, contains('<extensions><speed>40.0</speed></extensions>'));
    });

    test('KML 含 LineString 坐标与统计', () {
      final k = TrackExport.kml(trip(km: 12.3, track: line(3)));
      expect(k, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
      expect(k, contains('<LineString>'));
      expect(k, contains('120.000000,30.000000,0'));
      expect(k, contains('<Data name="distance_km"><value>12.30</value></Data>'));
    });

    test('名称里的 XML 特殊字符会转义', () {
      final g = TrackExport.gpx(trip(track: line(2)), name: 'A&B <测试>');
      expect(g, contains('A&amp;B &lt;测试&gt;'));
    });

    test('没有轨迹点也能导出合法 GPX 头尾', () {
      final g = TrackExport.gpx(trip());
      expect(g, contains('<trkseg>'));
      expect(g.trimRight(), endsWith('</gpx>'));
      expect(g, isNot(contains('<trkpt')));
    });
  });

  group('行程合并', () {
    test('里程/油耗/用时相加，轨迹首尾相接', () {
      final a = trip(ts: 2, km: 10, fuel: 0.8, sec: 600, track: line(3));
      final b = trip(ts: 1, km: 5, fuel: 0.4, sec: 300, track: line(2));
      final m = TripOps.merge([a, b]);
      expect(m.ts, 1);
      expect(m.km, 15);
      expect(m.fuel, closeTo(1.2, 1e-9));
      expect(m.sec, 900);
      expect(m.track.length, 5);
      expect(m.vehicleId, 'v1');
    });

    test('轨迹点过多会抽稀到 600', () {
      final a = trip(track: line(400));
      final b = trip(track: line(400));
      final m = TripOps.merge([a, b]);
      expect(m.track.length, 600);
      expect(m.track.first, a.track.first);
    });

    test('空列表报错', () {
      expect(() => TripOps.merge([]), throwsArgumentError);
    });
  });

  group('行程拆分', () {
    test('按轨迹比例切分，里程相加等于原值', () {
      final t = trip(km: 10, fuel: 1, sec: 600, track: line(10));
      final parts = TripOps.split(t, 0.5);
      expect(parts.length, 2);
      expect(parts[0].km + parts[1].km, closeTo(10, 1e-9));
      expect(parts[0].fuel + parts[1].fuel, closeTo(1, 1e-9));
      expect(parts[0].sec + parts[1].sec, closeTo(600, 1e-9));
      expect(parts[0].track.length, 6);
      expect(parts[1].track.length, 5);
      expect(parts[1].ts, greaterThan(parts[0].ts));
    });

    test('没有轨迹时按时间切', () {
      final t = trip(km: 10, fuel: 1, sec: 600);
      final parts = TripOps.split(t, 0.25);
      expect(parts[0].km, closeTo(2.5, 1e-9));
      expect(parts[1].km, closeTo(7.5, 1e-9));
      expect(parts[0].sec, closeTo(150, 1e-9));
      expect(parts[0].track, isEmpty);
    });

    test('比例被限制在 0.1–0.9', () {
      final t = trip(km: 10, track: line(10));
      final parts = TripOps.split(t, 5);
      expect(parts[0].km, closeTo(9, 1e-6));
    });
  });

  group('TripRec 序列化', () {
    test('vehicleId 能往返', () {
      final t = trip(vehicleId: 'v42');
      final back = TripRec.fromJson(t.toJson());
      expect(back.vehicleId, 'v42');
      expect(back.km, t.km);
      expect(back.track.length, t.track.length);
    });
  });
}
