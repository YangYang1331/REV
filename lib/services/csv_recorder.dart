import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:obd_dashboard/core/export/csv_logger.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 实时 PID CSV 录制器：一键开始/结束，把每帧写入外部目录。
class CsvRecorder {
  CsvRecorder();

  IOSink? _sink;
  File? _file;
  int _rows = 0;
  int _startMs = 0;
  bool get isRecording => _sink != null;
  int get rows => _rows;
  File? get file => _file;

  Future<File> start() async {
    if (_sink != null) {
      throw StateError('already recording');
    }
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final ts = DateTime.now();
    final name =
        'rev_pid_${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.csv';
    _file = File('${dir.path}/$name');
    _sink = _file!.openWrite();
    _sink!.writeln(CsvLogger.header);
    _startMs = DateTime.now().millisecondsSinceEpoch;
    _rows = 0;
    return _file!;
  }

  /// 喂一帧（按时间采样，至少间隔 ~100ms）。
  void feed(ObdData d) {
    final s = _sink;
    if (s == null) return;
    final rel = DateTime.now().millisecondsSinceEpoch - _startMs;
    s.writeln(CsvLogger.row(
      timeMs: rel,
      rpm: d.rpm,
      speedKmh: d.speed,
      coolantC: d.coolant,
      voltageV: d.voltage,
      gear: d.gear,
    ));
    _rows++;
  }

  Future<String> stop() async {
    final s = _sink;
    if (s == null) return '';
    await s.flush();
    await s.close();
    _sink = null;
    final path = _file?.path ?? '';
    debugPrint('csv saved: $path ($_rows rows)');
    return path;
  }
}
