import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/export/csv_logger.dart';

void main() {
  group('CsvLogger', () {
    test('表头稳定', () {
      expect(CsvLogger.header, 'time_ms,rpm,speed_kmh,coolant_c,voltage_v,gear');
    });

    test('一行格式：数值固定位、空值为空串', () {
      final row = CsvLogger.row(
        timeMs: 1000,
        rpm: 3000,
        speedKmh: 55.5,
        coolantC: 90,
        voltageV: 12.45,
        gear: 3,
      );
      expect(row, '1000,3000,55.5,90.0,12.45,3');
    });

    test('null 字段输出空串而非 NaN', () {
      final row = CsvLogger.row(timeMs: 0, rpm: 0, speedKmh: 0, gear: 0);
      expect(row, '0,0,0.0,,,0');
    });

    test('字段数与表头一致', () {
      final row = CsvLogger.row(timeMs: 1, rpm: 1, speedKmh: 1, gear: 1);
      expect(row.split(',').length, CsvLogger.header.split(',').length);
    });
  });
}
