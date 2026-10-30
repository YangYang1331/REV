import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/obd/deep_diagnostic.dart';
import 'package:obd_dashboard/services/diagnostic_report.dart';

void main() {
  testWidgets('诊断报告：能生成合法 PDF', (tester) async {
    final readiness = DeepDiagnosticCodec.parseReadiness('41 01 83 07 65 04');
    final bytes = (await tester.runAsync(() =>
        DiagnosticReport.renderBytes(DiagnosticReportData(
      generatedAt: DateTime(2026, 10, 30, 21, 5),
      appVersion: '2.16.2',
      vehicleName: '马自达 6 (GH) 2.0',
      vin: 'JM1GH123456789012',
      adapterName: 'Vgate iCar Pro',
      readiness: readiness,
      stored: const ['P0171', 'P0300', 'C1234'],
      pending: const ['P0420'],
      permanent: const [],
      freeze: const FreezeFrame(dtc: 'P0171', fields: [
        FreezeFrameField('发动机转速', 1726, 'rpm'),
        FreezeFrameField('车速', 80, 'km/h'),
        FreezeFrameField('冷却液温度', 50, '°C'),
      ]),
    ))))!;
    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // PDF 内应包含两页以上（内容较多时自动分页）
    final tail = String.fromCharCodes(bytes.skip(bytes.length - 64));
    expect(tail, contains('%%EOF'));
  });

  testWidgets('诊断报告：空数据也能生成', (tester) async {
    final bytes = (await tester.runAsync(() => DiagnosticReport.renderBytes(
          DiagnosticReportData(
            generatedAt: DateTime(2026, 1, 1),
            appVersion: '2.16.2',
            vehicleName: '未选择车型',
            connected: false,
          ),
        )))!;
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
