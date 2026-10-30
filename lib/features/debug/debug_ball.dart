import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/services/crash_guard.dart';
import 'package:obd_dashboard/services/obd_service.dart';

/// 调试悬浮球：仅在 debug 构建中出现（外层用 `if (kDebugMode) DebugBall()` 控制）。
///
///  - 可自由拖动（松手停在当前位置）；
///  - 单击展开半透明面板：崩溃日志（可清空）、连接状态（阶段/错误/重连次数）、
///    最近一帧关键数值（转速/车速/水温/电压/数据源）；
///  - 再次单击球或面板上的关闭按钮收起。
///
/// release 构建中因外层 `kDebugMode` 判断而完全不会被插入，零体积影响。
class DebugBall extends ConsumerStatefulWidget {
  const DebugBall({super.key});

  @override
  ConsumerState<DebugBall> createState() => _DebugBallState();
}

class _DebugBallState extends ConsumerState<DebugBall> {
  Offset _pos = const Offset(16, 90);
  bool _open = false;
  List<String> _logs = const [];
  ObdConnState _conn = const ObdConnState(stage: ObdConnStage.idle);

  @override
  void initState() {
    super.initState();
    // 监听连接状态变化
    final svc = ref.read(obdServiceProvider);
    svc.connState.addListener(_onConnChanged);
    _conn = svc.connState.value;
    _reloadLogs();
  }

  void _onConnChanged() {
    if (!mounted) return;
    setState(() => _conn = ref.read(obdServiceProvider).connState.value);
  }

  Future<void> _reloadLogs() async {
    final l = await CrashGuard.readLogs();
    if (!mounted) return;
    setState(() => _logs = l);
  }

  Future<void> _clearLogs() async {
    await CrashGuard.clearLogs();
    await _reloadLogs();
  }

  @override
  void dispose() {
    try {
      ref.read(obdServiceProvider).connState.removeListener(_onConnChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 实时遥测帧（仅在面板打开时刷新，避免每帧重建）
    final tele = ref.watch(telemetryProvider);
    final d = tele.current;

    return Stack(
      children: [
        // 面板
        if (_open)
          Positioned(
            left: 16,
            top: 60,
            child: _Panel(
              conn: _conn,
              logs: _logs,
              rpm: d.rpm,
              speed: d.speed,
              coolant: d.coolant,
              voltage: d.voltage,
              source: d.source,
              offline: tele.isOffline,
              onClose: () => setState(() => _open = false),
              onClearLogs: _clearLogs,
              onRefreshLogs: _reloadLogs,
            ),
          ),
        // 悬浮球
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (e) {
              setState(() {
                _pos = Offset(
                  (_pos.dx + e.delta.dx).clamp(0.0, 800.0),
                  (_pos.dy + e.delta.dy).clamp(0.0, 400.0),
                );
              });
            },
            onTap: () => setState(() => _open = !_open),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.75),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const Icon(Icons.bug_report, size: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.conn,
    required this.logs,
    required this.rpm,
    required this.speed,
    required this.coolant,
    required this.voltage,
    required this.source,
    required this.offline,
    required this.onClose,
    required this.onClearLogs,
    required this.onRefreshLogs,
  });

  final ObdConnState conn;
  final List<String> logs;
  final int rpm;
  final double speed;
  final double? coolant;
  final double? voltage;
  final String source;
  final bool offline;
  final VoidCallback onClose;
  final VoidCallback onClearLogs;
  final VoidCallback onRefreshLogs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      constraints: const BoxConstraints(maxHeight: 360),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xCC101418),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withOpacity(0.6), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, size: 14, color: Colors.redAccent),
              const SizedBox(width: 6),
              const Text('DEBUG',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const Spacer(),
              IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: onClose,
              ),
            ],
          ),
          _kv('连接', '${conn.stage.name}${conn.reconnectAttempt > 0 ? ' (重试 ${conn.reconnectAttempt})' : ''}'),
          if (conn.lastError != null && conn.lastError!.isNotEmpty)
            _kv('错误', conn.lastError!, warn: true),
          _kv('帧', 'rpm=$rpm  spd=${speed.toStringAsFixed(0)}  cool=${coolant?.toStringAsFixed(0) ?? '--'}℃  v=${voltage?.toStringAsFixed(1) ?? '--'}V'),
          _kv('源', '$source${offline ? ' / offline' : ''}'),
          const Divider(color: Colors.white24, height: 12),
          Row(
            children: [
              const Text('日志',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              const Spacer(),
              TextButton(onPressed: onRefreshLogs, child: const Text('刷新', style: TextStyle(fontSize: 11))),
              TextButton(onPressed: onClearLogs, child: const Text('清空', style: TextStyle(fontSize: 11, color: Colors.redAccent))),
            ],
          ),
          Flexible(
            child: logs.isEmpty
                ? const Text('（无崩溃日志）',
                    style: TextStyle(color: Colors.white38, fontSize: 10))
                : ListView(
                    shrinkWrap: true,
                    children: logs
                        .map((l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(
                                l,
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 9),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(k,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    color: warn ? Colors.redAccent : Colors.white,
                    fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
