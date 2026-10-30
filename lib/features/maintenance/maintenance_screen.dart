import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';

/// 保养提醒：机油 / 轮胎 / 年检。
///
/// 车机读不到"总里程"这个标准 PID，所以用「用户填一次当前仪表里程 + App 累加行程里程」
/// 来推算；用户随时可以再填一次校准，偏差不会累积。
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  MaintState? _s;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AppStore.instance.loadMaintState();
    if (mounted) {
      setState(() {
        _s = s;
        _loading = false;
      });
    }
  }

  Future<void> _save(MaintState s) async {
    await AppStore.instance.saveMaintState(s);
    await _load();
  }

  Future<double?> _askNumber(String title, String hint,
      {double? initial}) async {
    final ctrl = TextEditingController(
        text: initial == null ? '' : initial.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text.trim())),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final s = _s;
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('保养提醒'),
      ),
      body: _loading || s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _odoCard(skin, s),
                const SizedBox(height: 14),
                _item(
                  skin,
                  icon: Icons.water_drop_outlined,
                  title: '机油 / 机油滤',
                  since: s.sinceOilKm,
                  limitKm: s.intervalOilKm.toDouble(),
                  hint: '建议每 ${s.intervalOilKm} km 或 12 个月',
                  onMark: () => _markOil(s),
                  onInterval: () => _editInterval(s, oil: true),
                ),
                _item(
                  skin,
                  icon: Icons.tire_repair,
                  title: '轮胎 / 四轮换位',
                  since: s.sinceTireKm,
                  limitKm: s.intervalTireKm.toDouble(),
                  hint: '建议每 ${s.intervalTireKm} km 检查一次（胎压建议每月）',
                  onMark: () => _markTire(s),
                  onInterval: () => _editInterval(s, oil: false),
                ),
                _item(
                  skin,
                  icon: Icons.verified_outlined,
                  title: '年检',
                  since: s.sinceInspectDays?.toDouble(),
                  limitKm: s.intervalInspectDays.toDouble(),
                  unit: '天',
                  hint: s.inspectDue == null
                      ? '每 ${s.intervalInspectDays} 天提醒一次'
                      : '到期 ${_ymd(s.inspectDue!)}',
                  onMark: () => _markInspect(s),
                ),
                _item(
                  skin,
                  icon: Icons.shield_outlined,
                  title: '保险',
                  since: s.sinceInsuranceDays?.toDouble(),
                  limitKm: s.intervalInsuranceDays.toDouble(),
                  unit: '天',
                  hint: s.insuranceDue == null
                      ? '每 ${s.intervalInsuranceDays} 天提醒一次'
                      : '到期 ${_ymd(s.insuranceDue!)}',
                  onMark: () => _markInsurance(s),
                ),
                const SizedBox(height: 10),
                Text(
                  '说明：这些提醒只在本机保存，不上传服务器。里程按"你填的仪表读数 + App 累计行程"推算，'
                  '换车/换表后重新填一次即可校准。',
                  style: TextStyle(color: skin.faint, fontSize: 11, height: 1.6),
                ),
              ],
            ),
    );
  }

  Widget _odoCard(skin, MaintState s) {
    final odo = s.currentOdoKm;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skin.accent2.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.accent2.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed, color: skin.accent2, size: 20),
              const SizedBox(width: 10),
              Text('当前总里程',
                  style: TextStyle(color: skin.dim, fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final v = await _askNumber('校准当前仪表里程', '例如 83500',
                      initial: odo);
                  if (v == null) return;
                  await _save(s.copyWith(
                      odoAnchorKm: v, odoAnchorAccumKm: s.accumKm));
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(odo == null ? '填写' : '校准'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            odo == null ? '--' : '${odo.toStringAsFixed(0)} km',
            style: TextStyle(
                color: skin.ink,
                fontFamily: 'DSEG7',
                fontSize: 30,
                fontWeight: FontWeight.bold),
          ),
          if (odo == null)
            Text('填一次仪表里程，之后 App 会自己累加，保养提醒才准。',
                style: TextStyle(color: skin.faint, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _item(
    skin, {
    required IconData icon,
    required String title,
    required double? since,
    required double limitKm,
    required String hint,
    required VoidCallback onMark,
    String unit = 'km',
    VoidCallback? onInterval,
  }) {
    final remain = since == null ? null : limitKm - since;
    final rm = remain ?? 0.0;
    final overdue = remain != null && remain <= 0;
    final soon = remain != null && remain > 0 && remain <= limitKm * 0.15;
    final color = since == null
        ? skin.dim
        : overdue
            ? skin.bad
            : soon
                ? skin.warn
                : skin.ok;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(color: skin.ink, fontSize: 14)),
              const Spacer(),
              if (since == null)
                Text('未记录', style: TextStyle(color: skin.faint, fontSize: 11))
              else
                Text(
                  overdue
                      ? '已超 ${(-rm).toStringAsFixed(0)} $unit'
                      : '还剩 ${rm.toStringAsFixed(0)} $unit',
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            since == null
                ? hint
                : '${unit == 'km' ? '已行驶' : '已过去'} ${since.toStringAsFixed(0)} $unit · $hint',
            style: TextStyle(color: skin.faint, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: onMark,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('刚做过，记录一下'),
              ),
              if (onInterval != null)
                TextButton.icon(
                  onPressed: onInterval,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('周期'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _markOil(MaintState s) async {
    final odo = s.currentOdoKm;
    if (odo == null) {
      final v = await _askNumber('填写当前仪表里程', '先填里程才能记录保养');
      if (v == null) return;
      await _save(s.copyWith(
          odoAnchorKm: v,
          odoAnchorAccumKm: s.accumKm,
          lastOilOdoKm: v));
      return;
    }
    await _save(s.copyWith(lastOilOdoKm: odo));
  }

  Future<void> _markTire(MaintState s) async {
    final odo = s.currentOdoKm;
    if (odo == null) {
      final v = await _askNumber('填写当前仪表里程', '先填里程才能记录保养');
      if (v == null) return;
      await _save(s.copyWith(
          odoAnchorKm: v, odoAnchorAccumKm: s.accumKm, lastTireOdoKm: v));
      return;
    }
    await _save(s.copyWith(lastTireOdoKm: odo));
  }

  Future<void> _markInspect(MaintState s) async {
    await _save(s.copyWith(
        lastInspectTs: DateTime.now().millisecondsSinceEpoch));
  }

  Future<void> _markInsurance(MaintState s) async {
    await _save(s.copyWith(
        lastInsuranceTs: DateTime.now().millisecondsSinceEpoch));
  }

  static String _ymd(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _editInterval(MaintState s, {required bool oil}) async {
    final v = await _askNumber(
        oil ? '机油保养间隔（km）' : '轮胎检查间隔（km）', '例如 8000',
        initial: (oil ? s.intervalOilKm : s.intervalTireKm).toDouble());
    if (v == null || v < 500) return;
    await _save(s.copyWith(
        intervalOilKm: oil ? v.round() : null,
        intervalTireKm: oil ? null : v.round()));
  }
}
