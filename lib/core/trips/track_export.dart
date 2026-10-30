/// 行程轨迹导出（GPX / KML）与行程合并 / 拆分。
///
/// 全部纯函数，不碰平台通道，方便单测：
///  - GPX 1.1：Google Earth / 奥维 / 佳明 / strava 类工具都认；
///  - KML 2.2：Google Earth、高德/百度（导入）能用；
///  - 没有逐点时间戳，按"起点时间 + 均匀分布"插值，够看轨迹形状。
library;

import 'package:obd_dashboard/core/store/app_store.dart';

class TrackExport {
  const TrackExport._();

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms).toUtc().toIso8601String();

  static String _name(TripRec t, String? name) =>
      name ?? 'REV 行程 ${DateTime.fromMillisecondsSinceEpoch(t.ts).toLocal()}';

  /// 导出 GPX 1.1 文本。
  static String gpx(TripRec t, {String? name}) {
    final title = _name(t, name);
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="REV" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <metadata>')
      ..writeln('    <name>${_esc(title)}</name>')
      ..writeln('    <time>${_iso(t.ts)}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_esc(title)}</name>')
      ..writeln('    <desc>${_esc(_summary(t))}</desc>')
      ..writeln('    <trkseg>');
    final n = t.track.length;
    for (var i = 0; i < n; i++) {
      final p = t.track[i];
      if (p.length < 2) continue;
      final ts = t.ts + (t.sec * 1000 * (n <= 1 ? 0 : i / (n - 1))).round();
      b.write('      <trkpt lat="${p[0].toStringAsFixed(6)}" '
          'lon="${p[1].toStringAsFixed(6)}">');
      if (p.length > 2) {
        // GPX 没有标准"速度"字段，放扩展里，主流工具会忽略但不影响轨迹。
        b.write('<time>${_iso(ts)}</time>'
            '<extensions><speed>${p[2].toStringAsFixed(1)}</speed></extensions>');
      } else {
        b.write('<time>${_iso(ts)}</time>');
      }
      b.writeln('</trkpt>');
    }
    b
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return b.toString();
  }

  /// 导出 KML 2.2 文本（LineString + 统计 ExtendedData）。
  static String kml(TripRec t, {String? name}) {
    final title = _name(t, name);
    final coords = t.track
        .where((p) => p.length >= 2)
        .map((p) => '${p[1].toStringAsFixed(6)},${p[0].toStringAsFixed(6)},0')
        .join(' ');
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<kml xmlns="http://www.opengis.net/kml/2.2">\n'
        '  <Document>\n'
        '    <name>${_esc(title)}</name>\n'
        '    <Placemark>\n'
        '      <name>${_esc(title)}</name>\n'
        '      <TimeStamp><when>${_iso(t.ts)}</when></TimeStamp>\n'
        '      <ExtendedData>\n'
        '        <Data name="distance_km"><value>${t.km.toStringAsFixed(2)}</value></Data>\n'
        '        <Data name="fuel_l"><value>${t.fuel.toStringAsFixed(2)}</value></Data>\n'
        '        <Data name="avg_kmh"><value>${t.avgSpeed.toStringAsFixed(0)}</value></Data>\n'
        '        <Data name="max_kmh"><value>${t.maxSpeed.toStringAsFixed(0)}</value></Data>\n'
        '        <Data name="score"><value>${t.score ?? ''}</value></Data>\n'
        '      </ExtendedData>\n'
        '      <LineString>\n'
        '        <tessellate>1</tessellate>\n'
        '        <coordinates>$coords</coordinates>\n'
        '      </LineString>\n'
        '    </Placemark>\n'
        '  </Document>\n'
        '</kml>\n';
  }

  static String _summary(TripRec t) {
    final l100 = t.l100 == null ? '油耗 --' : '油耗 ${t.l100!.toStringAsFixed(1)}L/100km';
    return '${t.km.toStringAsFixed(1)}km · 均速 ${t.avgSpeed.toStringAsFixed(0)}km/h · '
        '$l100${t.score == null ? '' : ' · 评分 ${t.score}'}';
  }
}

/// 行程合并 / 拆分。
class TripOps {
  const TripOps._();

  /// 把多段行程合并成一段（按开始时间排序）。
  ///
  /// 说明：轨迹是"首尾相接"，中间若车辆熄火过，轨迹会有一条直线连起来；
  /// UI 上会提示用户。里程/油耗/用时直接相加，评分由 getter 重新计算。
  static TripRec merge(List<TripRec> trips) {
    if (trips.isEmpty) {
      throw ArgumentError('至少需要一段行程');
    }
    final sorted = List<TripRec>.from(trips)..sort((a, b) => a.ts.compareTo(b.ts));
    var km = 0.0, fuel = 0.0, sec = 0.0, idle = 0.0, maxSpeed = 0.0;
    var ha = 0, hb = 0, viol = 0;
    final track = <List<double>>[];
    for (final t in sorted) {
      km += t.km;
      fuel += t.fuel;
      sec += t.sec;
      idle += t.idleSec;
      if (t.maxSpeed > maxSpeed) maxSpeed = t.maxSpeed;
      ha += t.harshAccel;
      hb += t.harshBrake;
      viol += t.violations;
      track.addAll(t.track);
    }
    return TripRec(
      ts: sorted.first.ts,
      km: km,
      fuel: fuel,
      sec: sec,
      maxSpeed: maxSpeed,
      harshAccel: ha,
      harshBrake: hb,
      idleSec: idle,
      violations: viol,
      vehicleId: sorted.first.vehicleId,
      track: _cap(track, 600),
    );
  }

  /// 按比例拆成两段（0.1–0.9）。有轨迹时按轨迹点切，否则按时间切。
  static List<TripRec> split(TripRec t, double fraction) {
    final f = fraction.clamp(0.1, 0.9);
    final track = t.track;
    double aKm, aFuel, aSec, aIdle;
    List<List<double>> aTrack = const [];
    List<List<double>> bTrack = const [];
    if (track.length >= 2) {
      final idx = (track.length * f).round().clamp(1, track.length - 1);
      final ratio = idx / track.length;
      aKm = t.km * ratio;
      aFuel = t.fuel * ratio;
      aSec = t.sec * ratio;
      aIdle = t.idleSec * ratio;
      aTrack = track.sublist(0, idx + 1);
      bTrack = track.sublist(idx);
    } else {
      aKm = t.km * f;
      aFuel = t.fuel * f;
      aSec = t.sec * f;
      aIdle = t.idleSec * f;
    }
    final bKm = t.km - aKm;
    final bFuel = t.fuel - aFuel;
    final bSec = t.sec - aSec;
    final bIdle = t.idleSec - aIdle;
    final a = TripRec(
      ts: t.ts,
      km: aKm,
      fuel: aFuel,
      sec: aSec,
      maxSpeed: t.maxSpeed,
      harshAccel: (t.harshAccel * (aSec / (t.sec <= 0 ? 1 : t.sec))).round(),
      harshBrake: (t.harshBrake * (aSec / (t.sec <= 0 ? 1 : t.sec))).round(),
      idleSec: aIdle,
      violations: (t.violations * (aSec / (t.sec <= 0 ? 1 : t.sec))).round(),
      vehicleId: t.vehicleId,
      track: aTrack,
    );
    final b = TripRec(
      ts: t.ts + (aSec * 1000).round(),
      km: bKm,
      fuel: bFuel,
      sec: bSec,
      maxSpeed: t.maxSpeed,
      harshAccel: t.harshAccel - a.harshAccel,
      harshBrake: t.harshBrake - a.harshBrake,
      idleSec: bIdle,
      violations: t.violations - a.violations,
      vehicleId: t.vehicleId,
      track: bTrack,
    );
    return [a, b];
  }

  /// 轨迹点太多就等距抽稀，避免存档和导出体积失控。
  static List<List<double>> _cap(List<List<double>> pts, int max) {
    if (pts.length <= max) return List<List<double>>.from(pts);
    final out = <List<double>>[];
    final step = (pts.length - 1) / (max - 1);
    for (var i = 0; i < max; i++) {
      out.add(pts[(i * step).round()]);
    }
    return out;
  }
}
