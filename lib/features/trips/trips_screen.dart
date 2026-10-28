import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/trips/trip_detail_screen.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  List<TripRec> _trips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await AppStore.instance.loadTrips();
    if (mounted) setState(() => _trips = l);
  }

  String _fmtTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtDuration(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).round();
    return '${m}分${s.toString().padLeft(2, '0')}秒';
  }

  Future<void> _endTrip() async {
    await ref.read(telemetryProvider).resetTrip();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('行程已存档并清零')),
      );
    }
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空全部历史行程？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await AppStore.instance.clearTrips();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    final d = t.current;
    final skin = ref.watch(skinProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('行程记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
            onPressed: _clearHistory,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _currentCard(d, skin),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('历史行程（${_trips.length}）',
                  style: TextStyle(color: skin.dim, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _endTrip,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('结束并清零'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_trips.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('暂无历史行程，结束一段行程后会自动存档',
                    style: TextStyle(color: skin.faint, fontSize: 13)),
              ),
            )
          else
            ..._trips.map((r) => _tripCard(r)),
        ],
      ),
    );
  }

  Widget _currentCard(d, skin) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.panelStroke),
      ),
      child: Column(
        children: [
          Text('当前行程', style: TextStyle(color: skin.dim, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('${d.tripKm.toStringAsFixed(1)}', 'km', '里程', skin),
              _stat(d.tripL100?.toStringAsFixed(1) ?? '--', 'L/100', '平均油耗', skin),
              _stat(d.tripFuel.toStringAsFixed(2), 'L', '耗油', skin),
              _stat('${d.tripAvgSpeed.toStringAsFixed(0)}', 'km/h', '均速', skin),
            ],
          ),
          const SizedBox(height: 12),
          Text('用时 ${_fmtDuration(d.tripSec)}',
              style: TextStyle(color: skin.dim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _stat(String v, String unit, String label, skin) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(v,
                style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                    color: skin.ink)),
            const SizedBox(width: 3),
            Text(unit, style: TextStyle(color: skin.dim, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: skin.dim, fontSize: 11)),
      ],
    );
  }

  Widget _tripCard(TripRec r) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TripDetailScreen(trip: r),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtTime(r.ts),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('用时 ${_fmtDuration(r.sec)} · 均速 ${r.avgSpeed.toStringAsFixed(0)} km/h',
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11)),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${r.km.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        fontFamily: 'DSEG7', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                const SizedBox(height: 2),
                Text(r.l100 == null ? '油耗 --' : '${r.l100!.toStringAsFixed(1)} L/100',
                    style: const TextStyle(color: Color(0xFFF2B23B), fontSize: 12)),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}
