import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/config/environment.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_advice.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';
import 'package:obd_dashboard/core/obd/deep_diagnostic.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/diagnostic/symptom_check_screen.dart';
import 'package:obd_dashboard/services/diagnostic_report.dart';
import 'package:open_filex/open_filex.dart';

/// 深度诊断：排放就绪 / 待定码 / 永久码 / 冻结帧。
///
/// 这些数据比 Mode 03 更能说明"故障到什么程度"：
/// 待定码是早期预警，永久码清不掉，冻结帧记录故障发生瞬间的工况。
class DeepDiagnosticScreen extends ConsumerStatefulWidget {
  const DeepDiagnosticScreen({super.key});

  @override
  ConsumerState<DeepDiagnosticScreen> createState() =>
      _DeepDiagnosticScreenState();
}

class _DeepDiagnosticScreenState extends ConsumerState<DeepDiagnosticScreen> {
  ReadinessReport? _readiness;
  List<String> _pending = const [];
  List<String> _permanent = const [];
  FreezeFrame? _freeze;
  bool _loading = false;
  bool _loadingFreeze = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final obd = ref.read(obdServiceProvider);
    if (!obd.isConnected) return;
    setState(() => _loading = true);
    try {
      final readiness = await obd.readReadiness();
      final pending = await obd.readPendingDtcs();
      final permanent = await obd.readPermanentDtcs();
      if (!mounted) return;
      setState(() {
        _readiness = readiness;
        _pending = pending;
        _permanent = permanent;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFreeze() async {
    final obd = ref.read(obdServiceProvider);
    if (!obd.isConnected || _loadingFreeze) return;
    setState(() => _loadingFreeze = true);
    try {
      final f = await obd.readFreezeFrame();
      if (mounted) setState(() => _freeze = f);
    } finally {
      if (mounted) setState(() => _loadingFreeze = false);
    }
  }

  /// 生成 PDF 诊断报告并交给系统打开/分享。
  Future<void> _exportReport() async {
    if (_exporting) return;
    final obd = ref.read(obdServiceProvider);
    if (!obd.isConnected) {
      _toast('请先连接 OBD 适配器，再生成诊断报告。');
      return;
    }
    setState(() => _exporting = true);
    try {
      final stored = await obd.readDtcs();
      final readiness = _readiness ?? await obd.readReadiness();
      final pending =
          _pending.isNotEmpty ? _pending : await obd.readPendingDtcs();
      final permanent =
          _permanent.isNotEmpty ? _permanent : await obd.readPermanentDtcs();
      final freeze = _freeze;
      final profileId = await AppStore.instance.getProfile();
      final vehicle = VehicleProfile.byId(profileId ?? '');
      final vin = await AppStore.instance.getLastVin();
      final adapter = await AppStore.instance.getKnownDeviceName();
      final file = await DiagnosticReport.save(DiagnosticReportData(
        generatedAt: DateTime.now(),
        appVersion: AppEnvironment.version,
        vehicleName: vehicle.name,
        vin: vin,
        adapterName: adapter,
        readiness: readiness,
        stored: stored,
        pending: pending,
        permanent: permanent,
        freeze: freeze,
      ));
      if (!mounted) return;
      _toast('报告已生成：${file.path.split('/').last}');
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) _toast('生成报告失败：$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final obd = ref.watch(obdServiceProvider);
    final connected = obd.isConnected;
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('深度诊断'),
        actions: [
          IconButton(
            tooltip: '症状自查（离线）',
            icon: const Icon(Icons.psychology_alt_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SymptomCheckScreen())),
          ),
          IconButton(
            tooltip: '生成 PDF 诊断报告',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: connected && !_exporting && !_loading ? _exportReport : null,
          ),
          IconButton(
            tooltip: '重新读取',
            icon: const Icon(Icons.refresh),
            onPressed: connected && !_loading ? _load : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!connected) _hintCard(skin),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_readiness != null) ...[
            _readinessCard(skin, _readiness!),
            const SizedBox(height: 14),
          ],
          _codesCard(skin, '待定故障码（Mode 07）', _pending,
              '故障已发生但尚未确认，通常是早期预警'),
          const SizedBox(height: 14),
          _codesCard(skin, '永久故障码（Mode 0A）', _permanent,
              '清除后仍保留，需 ECU 自检通过才会消失'),
          const SizedBox(height: 14),
          _freezeCard(skin),
          const SizedBox(height: 18),
          Text(
            '说明：Mode 06 车载监控结果各厂商定义不一致，本版暂不做统一解析，'
            '避免给出误判；可结合 4S 店诊断仪读取。',
            style: TextStyle(color: skin.dim.withValues(alpha: 0.6), fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _hintCard(SkinDescriptor skin) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: skin.dim, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '请先连接 OBD 适配器并保持点火（ON 档），再进入深度诊断。',
                style: TextStyle(color: skin.dim, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _readinessCard(SkinDescriptor skin, ReadinessReport r) {
    final bad = r.milOn || r.incomplete.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (bad ? skin.warn : skin.ok).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(bad ? Icons.warning_amber : Icons.verified_outlined,
                  color: bad ? skin.warn : skin.ok, size: 20),
              const SizedBox(width: 8),
              Text(
                r.ready ? '排放就绪：全部完成' : '排放就绪：还有 ${r.incomplete.length} 项未完成',
                style: TextStyle(
                    color: skin.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '故障灯 ${r.milOn ? "点亮" : "未亮"} · ECU 报告 ${r.dtcCount} 个故障码',
            style: TextStyle(color: skin.dim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in r.monitors)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (m.complete ? skin.ok : skin.warn)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${m.complete ? "✓" : "…"} ${m.name}',
                    style: TextStyle(
                      color: m.complete ? skin.ok : skin.warn,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _codesCard(
      SkinDescriptor skin, String title, List<String> codes, String note) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: skin.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(note, style: TextStyle(color: skin.dim, fontSize: 11)),
          const SizedBox(height: 10),
          if (codes.isEmpty)
            Text('无', style: TextStyle(color: skin.dim, fontSize: 13))
          else
            ...codes.map((c) => _codeAdviceRow(skin, c)),
        ],
      ),
    );
  }

  /// 故障码一行：码 + 中文含义 + 严重度 + 参考费用；点开看能否继续开与自查。
  Widget _codeAdviceRow(SkinDescriptor skin, String code) {
    final info = DtcDatabase.explain(code);
    final a = DtcAdvice.of(code);
    final color = switch (a.severity) {
      2 => skin.bad,
      1 => skin.warn,
      _ => skin.ok,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => _showAdvice(code, a, info.title),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(code,
                    style: TextStyle(
                        color: skin.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace')),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(info.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.ink, fontSize: 12.5)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(a.severityLabel,
                      style: TextStyle(
                          color: color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text('参考费用：${a.cost}',
                style: TextStyle(color: skin.dim, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  void _showAdvice(String code, DtcAdvice a, String title) {
    final color = switch (a.severity) {
      2 => const Color(0xFFFF5C5C),
      1 => const Color(0xFFFFB020),
      _ => const Color(0xFF41E39B),
    };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B0F14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(code,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(a.severityLabel,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _sheetLine(Icons.directions_car, a.canDrive),
              const SizedBox(height: 8),
              _sheetLine(Icons.payments_outlined, '参考费用：${a.cost}'),
              if (a.tip != null) ...[
                const SizedBox(height: 8),
                _sheetLine(Icons.tips_and_updates_outlined, a.tip!),
              ],
              const SizedBox(height: 14),
              const Text('可以先自己查',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...a.selfCheck.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e.key + 1}. ',
                            style: TextStyle(color: color, fontSize: 12.5)),
                        Expanded(
                          child: Text(e.value,
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                  height: 1.5)),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetLine(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12.5, height: 1.5)),
          ),
        ],
      );

  Widget _freezeCard(SkinDescriptor skin) {
    final f = _freeze;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('冻结帧（故障瞬间工况）',
                    style: TextStyle(
                        color: skin.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _loadingFreeze ? null : _loadFreeze,
                child: Text(_loadingFreeze ? '读取中…' : (f == null ? '读取' : '重读')),
              ),
            ],
          ),
          if (f == null)
            Text('读取触发故障码那一刻的转速、车速、水温、负荷等快照。',
                style: TextStyle(color: skin.dim, fontSize: 11))
          else if (f.isEmpty)
            Text('本车 ECU 未提供冻结帧。', style: TextStyle(color: skin.dim, fontSize: 12))
          else ...[
            if (f.dtc != null)
              Text('触发码：${f.dtc}',
                  style: TextStyle(color: skin.warn, fontSize: 12)),
            const SizedBox(height: 8),
            for (final e in f.fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.label,
                          style: TextStyle(color: skin.dim, fontSize: 12)),
                    ),
                    Text(e.display,
                        style: TextStyle(color: skin.ink, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
