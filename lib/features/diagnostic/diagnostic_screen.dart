import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/diagnostic/data_stream_screen.dart';

class DiagnosticScreen extends ConsumerStatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  ConsumerState<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends ConsumerState<DiagnosticScreen> {
  String? _expandedCode;

  /// 实车模式下从 ECU 读到的故障码列表。
  List<String> _liveCodes = const [];
  bool _loadingCodes = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCodes());
  }

  /// 实车模式且 OBD 已连接 → 拉一次 Mode 03。
  Future<void> _refreshCodes() async {
    final tele = ref.read(telemetryProvider);
    final obd = ref.read(obdServiceProvider);
    if (!tele.isRealMode || !obd.isConnected) {
      if (mounted) setState(() => _liveCodes = const []);
      return;
    }
    if (mounted) setState(() => _loadingCodes = true);
    try {
      final codes = await obd.readDtcs();
      if (mounted) setState(() => _liveCodes = codes);
    } catch (_) {
      // 读失败保持上次状态
    } finally {
      if (mounted) setState(() => _loadingCodes = false);
    }
  }

  /// 清除故障码：二次确认 → Mode 04 → 重读 Mode 03。
  Future<void> _confirmAndClear() async {
    final obd = ref.read(obdServiceProvider);
    if (!obd.isConnected || _clearing) return;

    // 二次确认：明确告知 MIL 熄灭 ≠ 故障修复。
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除故障码？'),
        content: const Text(
          '将向 ECU 发送 Mode 04 清除指令：\n\n'
          '· 仪表盘 MIL 故障灯会熄灭；\n'
          '· 但故障本身并未修复，行驶后可能再次点亮；\n'
          '· 建议先排除机械/传感器故障再清除。\n\n'
          '确认继续？',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _clearing = true);
    final result = await obd.clearDtcs();
    if (!mounted) return;
    setState(() => _clearing = false);

    final msg = result.ok
        ? (result.aliveCodes.isEmpty
            ? '故障码已清除，MIL 应熄灭'
            : '清除指令已发，但仍有码：${result.aliveCodes.join(", ")}')
        : '清除失败：${result.error ?? "ECU 未响应"}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _refreshCodes();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    final d = t.current;
    final skin = ref.watch(skinProvider);
    final obd = ref.watch(obdServiceProvider);

    // 故障码：演示模式显示示例；实车模式用 ECU 实读；GPS/离线不显示。
    final codes = d.isDemo
        ? DtcDatabase.demoCodes
        : (t.isRealMode ? _liveCodes : const <String>[]);

    // 清码按钮可用条件：仅 OBD 真实连接时可用；demo/gps 置灰。
    final canClear = obd.isConnected && t.isRealMode && !_clearing;

    final rows = <_Row>[
      _Row('发动机转速', '${d.rpm}', 'RPM'),
      _Row('车速', d.speed.toStringAsFixed(0), 'km/h'),
      _Row('档位', d.gear <= 0 ? 'N' : '${d.gear}', '挡'),
      _Row('冷却液温度', d.coolant?.toStringAsFixed(0), '°C'),
      _Row('机油温度', d.oilTemp?.toStringAsFixed(0), '°C'),
      _Row('进气温度', d.intakeTemp?.toStringAsFixed(0), '°C'),
      _Row('环境温度', d.ambient?.toStringAsFixed(0), '°C'),
      _Row('进气歧管压力', d.map?.toStringAsFixed(0), 'kPa'),
      _Row('增压', d.boost?.toStringAsFixed(2), 'bar'),
      _Row('空气流量', d.maf?.toStringAsFixed(1), 'g/s'),
      _Row('发动机负荷', d.load?.toStringAsFixed(0), '%'),
      _Row('绝对负载', d.absLoad?.toStringAsFixed(0), '%'),
      _Row('节气门开度', d.throttle?.toStringAsFixed(0), '%'),
      _Row('点火提前角', d.ignAdv?.toStringAsFixed(1), '°'),
      _Row('长期燃油修正', d.ltft?.toStringAsFixed(1), '%'),
      _Row('燃油液位', d.fuelLevel?.toStringAsFixed(0), '%'),
      _Row('瞬时油耗', d.fuelLph?.toStringAsFixed(2), 'L/h'),
      _Row('燃油轨压力', d.fuelRailP?.toStringAsFixed(3), 'MPa'),
      _Row('催化器温度', d.catTemp?.toStringAsFixed(0), '°C'),
      _Row('变速箱油温', d.atfTemp?.toStringAsFixed(0), '°C'),
      _Row('海拔(反算)', d.altitude?.toStringAsFixed(0), 'm'),
      _Row('电瓶电压', d.voltage?.toStringAsFixed(2), 'V'),
    ];

    final shown = d.isDemo ? rows : rows.where((r) => r.value != null).toList();

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('诊断 / 故障码'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── 故障码区域 ──
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('故障码（DTC）',
                      style: TextStyle(
                          color: skin.dim,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1)),
                ),
                if (_loadingCodes)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    tooltip: '重新读取',
                    icon: const Icon(Icons.refresh, size: 18),
                    color: skin.dim,
                    onPressed: t.isRealMode ? _refreshCodes : null,
                  ),
                OutlinedButton.icon(
                  onPressed: canClear ? _confirmAndClear : null,
                  icon: _clearing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_sweep, size: 16),
                  label: Text(_clearing ? '清除中' : '清除故障码'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (codes.isEmpty)
            _noDtcCard(skin)
          else
            ...codes.map((c) => _dtcCard(c, skin)),
          const SizedBox(height: 20),

          // ── 实时数据流 ──
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Row(
              children: [
                Text('实时数据流',
                    style: TextStyle(
                        color: skin.dim,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.list_alt, size: 16),
                  label: const Text('全 PID 实时流'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DataStreamScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: (d.isDemo ? skin.warn : skin.ok).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (d.isDemo ? skin.warn : skin.ok)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              d.isDemo
                  ? '当前为离线演示模式，以下为模拟数据。连接真实 ELM327 后，仅显示本车 ECU 实际支持的 PID。'
                  : '已按本车 ECU 支持的 PID 自动隐藏不支持的项（共 ${shown.length}/${rows.length} 项）。',
              style: TextStyle(
                  color: d.isDemo ? skin.warn : skin.ok,
                  fontSize: 12,
                  height: 1.5),
            ),
          ),
          ...shown.map((r) => _rowTile(r)),
          const SizedBox(height: 12),
          Text(
            '说明：ATF 油温、催化器温度、燃油轨压力、点火提前等无统一标准 PID，多数 ECU 不广播；本车不支持时自动隐藏。',
            style: TextStyle(color: skin.faint, fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ── 无故障码 ──
  Widget _noDtcCard(skin) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: skin.ok.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.ok.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: skin.ok, size: 24),
          const SizedBox(width: 12),
          Text('未检测到故障码',
              style: TextStyle(
                  color: skin.ok,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── 故障码卡片（可展开） ──
  Widget _dtcCard(String code, skin) {
    // explain：字典命中给精确解释，未收录则按 SAE J2012 码位规则给出
    // 标准分类与通用说明，保证任何故障码都有解释、不出现空白。
    final info = DtcDatabase.explain(code);
    final expanded = _expandedCode == code;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: skin.bad.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.bad.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _expandedCode = expanded ? null : code;
            }),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: skin.bad,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(code,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'DSEG7')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(info.title,
                              style: TextStyle(
                                  color: skin.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (info.isGeneric) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: skin.dim.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('标准解析',
                                style: TextStyle(
                                    color: skin.dim,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: skin.dim,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: skin.bad.withValues(alpha: 0.2)),
                  const SizedBox(height: 8),
                  _detailBlock('故障说明', info.desc, skin),
                  const SizedBox(height: 10),
                  Text('可能原因',
                      style: TextStyle(
                          color: skin.warn,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...info.causes.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 3, left: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('· ',
                                style: TextStyle(color: skin.dim, fontSize: 13)),
                            Expanded(
                              child: Text(c,
                                  style: TextStyle(
                                      color: skin.dim,
                                      fontSize: 13,
                                      height: 1.4)),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 10),
                  _detailBlock('处理建议', info.suggestion, skin),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailBlock(String label, String text, skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: skin.accent,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(text,
            style: TextStyle(color: skin.dim, fontSize: 13, height: 1.5)),
      ],
    );
  }

  Widget _rowTile(_Row r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(r.label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(r.value ?? '--',
                  style: const TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.white)),
              const SizedBox(width: 5),
              Text(r.unit, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row {
  _Row(this.label, this.value, this.unit);
  final String label;
  final String? value;
  final String unit;
}
