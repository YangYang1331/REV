import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_advice.dart';
import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/diagnostic/data_stream_screen.dart';
import 'package:obd_dashboard/features/diagnostic/deep_diagnostic_screen.dart';
import 'package:obd_dashboard/services/obd_service.dart';

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
        actions: [
          IconButton(
            tooltip: '深度诊断（就绪 / 待定码 / 冻结帧）',
            icon: const Icon(Icons.troubleshoot),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DeepDiagnosticScreen())),
          ),
        ],
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
            // 严重度优先：能让你马上停车的码排在最前面，提示类码放最后。
            ..._sortedByRisk(codes).map((c) => _dtcCard(c, skin)),
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
          const SizedBox(height: 16),

          // ── 马自达扩展数据 / 手工命令 ──
          const _Mode22Panel(),
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
                  const SizedBox(height: 12),
                  _adviceBlock(code, skin),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _sortedByRisk(List<String> codes) {
    final l = List<String>.from(codes);
    l.sort((a, b) {
      final ra = DtcAdvice.of(a).severity;
      final rb = DtcAdvice.of(b).severity;
      if (ra != rb) return rb.compareTo(ra);
      return a.compareTo(b);
    });
    return l;
  }

  /// 严重度 / 能否继续开 / 维修预算 / 自查三步（P1「维修建议」）。
  Widget _adviceBlock(String code, skin) {
    final a = DtcAdvice.of(code);
    final color = switch (a.severity) {
      2 => skin.bad,
      1 => skin.warn,
      _ => skin.ok,
    };
    final rows = <Widget>[
      _adviceRow(Icons.report_gmailerrorred, '严重度：${a.severityLabel}', color, skin),
      _adviceRow(Icons.directions_car, a.canDrive, skin.ink, skin),
      _adviceRow(Icons.payments_outlined, '参考费用：${a.cost}', skin.dim, skin),
    ];
    if (a.tip != null) {
      rows.add(_adviceRow(Icons.tips_and_updates_outlined, a.tip!, skin.accent, skin));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          const SizedBox(height: 8),
          Text('自己能先查的三步',
              style: TextStyle(
                  color: skin.dim, fontSize: 12, fontWeight: FontWeight.bold)),
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
                          style: TextStyle(
                              color: skin.dim, fontSize: 12.5, height: 1.45)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _adviceRow(IconData icon, String text, Color color, skin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12.5, height: 1.45)),
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

/// 马自达扩展数据面板：Mode 22 支持位图探测 + 原始命令台 + 档位 K 值。
///
/// FORScan 的马自达 PID 表是逆向私有库，没有公开可信来源，所以不写死地址；
/// 这里直接向 ECU 询问它支持哪些 0x22 PID，再让用户按需读原始响应。
class _Mode22Panel extends ConsumerStatefulWidget {
  const _Mode22Panel();

  @override
  ConsumerState<_Mode22Panel> createState() => _Mode22PanelState();
}

class _Mode22PanelState extends ConsumerState<_Mode22Panel> {
  final TextEditingController _cmd = TextEditingController(text: '0902');
  bool _busy = false;
  int _progressBase = -1;
  String? _probeMsg;
  Mode22Result? _probe;
  String? _resp;

  @override
  void dispose() {
    _cmd.dispose();
    super.dispose();
  }

  Future<void> _probeMode22() async {
    final obd = ref.read(obdServiceProvider);
    setState(() {
      _busy = true;
      _probe = null;
      _resp = null;
      _probeMsg = '正在询问 ECU 支持哪些扩展 PID…';
    });
    try {
      final r = await obd.probeMode22(onProgress: (b) {
        if (mounted) setState(() => _progressBase = b);
      });
      if (!mounted) return;
      setState(() {
        _probe = r;
        _probeMsg = r.summary;
      });
    } catch (e) {
      if (mounted) setState(() => _probeMsg = '探测失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressBase = -1;
        });
      }
    }
  }

  Future<void> _sendRaw() async {
    final obd = ref.read(obdServiceProvider);
    setState(() {
      _busy = true;
      _resp = null;
    });
    try {
      final r = await obd.sendRaw(_cmd.text);
      if (mounted) setState(() => _resp = r);
    } catch (e) {
      if (mounted) setState(() => _resp = '发送失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final t = ref.watch(telemetryProvider);
    final d = t.current;
    final obd = ref.watch(obdServiceProvider);
    final kt = t.profile.gearKTable();
    final k = d.speed >= 3 ? d.rpm / d.speed : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 16, color: skin.accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('马自达扩展数据（Mode 22）',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ),
              if (!obd.isConnected)
                Text('未连接', style: TextStyle(color: skin.faint, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '马自达专用参数（变速箱油温、转向角、里程等）走 UDS 0x22 服务，'
            '地址因车而异且未公开。点击探测，ECU 会回报它真正支持的 PID 掩码；'
            '再用下方命令台按需读取原始响应。',
            style: TextStyle(color: skin.dim, fontSize: 11.5, height: 1.6),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: (_busy || !obd.isConnected) ? null : _probeMode22,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('探测扩展 PID'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: skin.accent,
                  side: BorderSide(color: skin.accent.withValues(alpha: 0.5)),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              if (_progressBase >= 0) ...[
                const SizedBox(width: 10),
                Text('22 ${_progressBase.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                    style: TextStyle(color: skin.dim, fontSize: 11)),
              ],
            ],
          ),
          if (_probeMsg != null) ...[
            const SizedBox(height: 10),
            Text(_probeMsg!,
                style: TextStyle(color: skin.dim, fontSize: 12, height: 1.5)),
          ],
          if (_probe != null && !_probe!.isEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _probe!.labels.take(64).map((s) {
                final pid = s.replaceAll(' ', '');
                return InkWell(
                  onTap: () => setState(() => _cmd.text = pid),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: skin.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(s,
                        style: TextStyle(
                            color: skin.accent,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text('点上面任一 PID 可把它填进命令台（去掉空格即为完整请求）。',
                style: TextStyle(color: skin.faint, fontSize: 10.5)),
          ],
          const SizedBox(height: 12),

          // 档位反推实时检视：K = rpm / km/h
          if (k != null && kt.isNotEmpty) ...[
            Text(
              '档位反推 K = 转速/车速 = ${k.toStringAsFixed(1)}  →  '
              '${d.gear <= 0 ? "N" : "${d.gear} 挡"}',
              style: TextStyle(
                  color: skin.ok, fontSize: 11.5, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            Text(
              '各挡理论 K：${[for (var i = 0; i < kt.length; i++) "${i + 1}挡 ${kt[i].toStringAsFixed(0)}"].join(" · ")}',
              style: TextStyle(color: skin.faint, fontSize: 10.5, height: 1.5),
            ),
            const SizedBox(height: 10),
          ],

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmd,
                  enabled: !_busy,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '例：010C / 0902 / 22 F4 0D',
                    hintStyle: TextStyle(color: skin.faint, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.14)),
                    ),
                  ),
                  onSubmitted: (_) => _sendRaw(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_busy || !obd.isConnected) ? null : _sendRaw,
                style: FilledButton.styleFrom(
                  backgroundColor: skin.accent,
                  minimumSize: const Size(0, 40),
                ),
                child: Text(_busy ? '…' : '发送',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_resp != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _resp!,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
