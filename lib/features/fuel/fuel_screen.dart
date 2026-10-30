import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/fuel/fuel_log.dart';
import 'package:obd_dashboard/core/garage/garage.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/maintenance/maintenance_screen.dart';

/// 油耗与用车账本。
///
/// 记每一次加油（里程 + 升数 + 单价），按"满箱到满箱"算真实长期油耗，
/// 顺带把保养 / 保险 / 年检到期提醒放在一页里。全部本机保存，不上传。
class FuelScreen extends ConsumerStatefulWidget {
  const FuelScreen({super.key});

  @override
  ConsumerState<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends ConsumerState<FuelScreen> {
  List<FuelRec> _records = const [];
  GarageVehicle? _vehicle;
  MaintState? _maint;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await AppStore.instance.loadFuelRecords();
    final v = await AppStore.instance.getActiveVehicle();
    final m = await AppStore.instance.loadMaintState();
    if (!mounted) return;
    setState(() {
      _vehicle = v;
      _maint = m;
      // 老记录没有 vehicleId，归当前车辆，避免升级后历史"消失"。
      _records = all
          .where((r) =>
              r.vehicleId.isEmpty ||
              v == null ||
              r.vehicleId == v.id)
          .toList();
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addRecord() async {
    final m = _maint;
    final added = await showDialog<FuelRec>(
      context: context,
      builder: (_) => _FuelDialog(
        initialOdo: m?.currentOdoKm,
        vehicleId: _vehicle?.id ?? '',
      ),
    );
    if (added == null) return;
    final all = await AppStore.instance.loadFuelRecords();
    all.add(added);
    await AppStore.instance.saveFuelRecords(all);
    await _load();
    _toast('已记录 ${added.liters.toStringAsFixed(1)} L');
  }

  Future<void> _deleteRecord(FuelRec r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这条加油记录？'),
        content: Text('${_date(r.ts)} · ${r.liters.toStringAsFixed(1)} L'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final all = await AppStore.instance.loadFuelRecords();
    all.removeWhere((e) => e.ts == r.ts && e.odo == r.odo);
    await AppStore.instance.saveFuelRecords(all);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final stats = FuelStats.of(_records);
    final sorted = List<FuelRec>.from(_records)
      ..sort((a, b) => b.ts.compareTo(a.ts));

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('油耗与账本'),
        actions: [
          IconButton(
            tooltip: '保养 / 保险 / 年检提醒',
            icon: const Icon(Icons.build_circle_outlined),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MaintenanceScreen()));
              await _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRecord,
        backgroundColor: skin.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.local_gas_station),
        label: const Text('记一笔加油'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _vehicleHeader(skin),
                const SizedBox(height: 12),
                _statsCard(skin, stats),
                const SizedBox(height: 12),
                _dueCard(skin),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('加油记录（${_records.length}）',
                        style: TextStyle(
                            color: skin.dim,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (stats.totalCost > 0)
                      Text('累计 ¥${stats.totalCost.toStringAsFixed(0)}',
                          style: TextStyle(color: skin.faint, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 8),
                if (sorted.isEmpty)
                  _empty(skin)
                else
                  ...sorted.map((r) => _recordCard(skin, r)),
                const SizedBox(height: 14),
                Text(
                  '算法：只统计"加满 → 加满"的区间（本次加油量 ÷ 区间里程），'
                  '半箱记录计入花费但不参与油耗；连续记满 2 次以上才有长期油耗。'
                  '数据仅存本机，不上传。',
                  style: TextStyle(color: skin.faint, fontSize: 11, height: 1.6),
                ),
              ],
            ),
    );
  }

  Widget _vehicleHeader(SkinDescriptor skin) {
    final v = _vehicle;
    final profile = v == null ? null : VehicleProfile.byId(v.profileId);
    return Row(
      children: [
        Icon(Icons.directions_car_outlined, size: 16, color: skin.accent2),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            v == null
                ? '未设置车辆'
                : '${v.name}${profile == null ? '' : ' · ${profile.name}'}'
                    '${v.vin.isEmpty ? '' : ' · VIN ${v.vin.substring(v.vin.length > 6 ? v.vin.length - 6 : 0)}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: skin.dim, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _statsCard(SkinDescriptor skin, FuelStats stats) {
    final trend = stats.trendL100;
    final trendText = trend == null
        ? '趋势：至少 4 箱才看得出'
        : trend.abs() < 0.05
            ? '趋势：基本持平'
            : trend > 0
                ? '趋势：↑ ${trend.abs().toStringAsFixed(1)} L/100（比早先更费）'
                : '趋势：↓ ${trend.abs().toStringAsFixed(1)} L/100（更省了）';
    final trendColor = trend == null
        ? skin.faint
        : trend > 0.05
            ? skin.warn
            : trend < -0.05
                ? skin.ok
                : skin.dim;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skin.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _metric(
                  skin,
                  stats.avgL100?.toStringAsFixed(1) ?? '--',
                  'L/100km',
                  '长期油耗',
                  big: true,
                ),
              ),
              Expanded(
                child: _metric(
                  skin,
                  stats.lastL100?.toStringAsFixed(1) ?? '--',
                  'L/100km',
                  '最近一箱',
                ),
              ),
              Expanded(
                child: _metric(
                  skin,
                  stats.costPerKm?.toStringAsFixed(2) ?? '--',
                  '元/km',
                  '每公里油费',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(trendText,
              style: TextStyle(color: trendColor, fontSize: 11.5)),
          const SizedBox(height: 8),
          Text(
            '累计 ${stats.totalLiters.toStringAsFixed(0)} L · '
            '¥${stats.totalCost.toStringAsFixed(0)} · ${stats.fills} 次加油',
            style: TextStyle(color: skin.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _metric(SkinDescriptor skin, String value, String unit, String label,
      {bool big = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: big ? 30 : 22,
                    color: skin.ink)),
            const SizedBox(width: 3),
            Text(unit, style: TextStyle(color: skin.faint, fontSize: 9.5)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: skin.dim, fontSize: 10.5)),
      ],
    );
  }

  Widget _dueCard(SkinDescriptor skin) {
    final m = _maint;
    final items = <_DueItem>[];
    if (m != null) {
      final sinceOil = m.sinceOilKm;
      if (sinceOil != null) {
        final remain = m.intervalOilKm - sinceOil;
        items.add(_DueItem(
          icon: Icons.water_drop_outlined,
          label: '机油保养',
          text: remain <= 0
              ? '已超 ${(-remain).toStringAsFixed(0)} km'
              : '还剩 ${remain.toStringAsFixed(0)} km',
          color: remain <= 0
              ? skin.bad
              : remain <= m.intervalOilKm * 0.15
                  ? skin.warn
                  : skin.ok,
        ));
      }
      final ins = m.insuranceDue;
      if (ins != null) {
        final d = ins.difference(DateTime.now()).inDays;
        items.add(_DueItem(
          icon: Icons.shield_outlined,
          label: '保险到期',
          text: d < 0 ? '已过期 ${-d} 天' : '${_ymd(ins)} · 还剩 $d 天',
          color: d < 0 ? skin.bad : d <= 30 ? skin.warn : skin.ok,
        ));
      }
      final insp = m.inspectDue;
      if (insp != null) {
        final d = insp.difference(DateTime.now()).inDays;
        items.add(_DueItem(
          icon: Icons.verified_outlined,
          label: '年检到期',
          text: d < 0 ? '已过期 ${-d} 天' : '${_ymd(insp)} · 还剩 $d 天',
          color: d < 0 ? skin.bad : d <= 30 ? skin.warn : skin.ok,
        ));
      }
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  size: 16, color: skin.accent2),
              const SizedBox(width: 8),
              Text('到期提醒',
                  style: TextStyle(
                      color: skin.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MaintenanceScreen()));
                  await _load();
                },
                child: const Text('设置'),
              ),
            ],
          ),
          if (items.isEmpty)
            Text('还没记录保养 / 保险 / 年检日期，点「设置」填一次，之后自动倒计时。',
                style: TextStyle(color: skin.dim, fontSize: 11.5, height: 1.5))
          else
            ...items.map((it) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(it.icon, size: 15, color: it.color),
                      const SizedBox(width: 8),
                      Text(it.label,
                          style:
                              TextStyle(color: skin.dim, fontSize: 12)),
                      const Spacer(),
                      Text(it.text,
                          style: TextStyle(
                              color: it.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _empty(SkinDescriptor skin) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.local_gas_station_outlined,
                color: skin.faint, size: 28),
            const SizedBox(height: 8),
            Text('还没有加油记录',
                style: TextStyle(color: skin.dim, fontSize: 13)),
            const SizedBox(height: 4),
            Text('每次加满后记一笔，两箱之后就能看到真实油耗。',
                style: TextStyle(color: skin.faint, fontSize: 11)),
          ],
        ),
      );

  Widget _recordCard(SkinDescriptor skin, FuelRec r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_date(r.ts),
                      style: TextStyle(
                          color: skin.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  if (r.full) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: skin.ok.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('加满',
                          style:
                              TextStyle(color: skin.ok, fontSize: 9.5)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${r.odo.toStringAsFixed(0)} km · '
                '${r.unitPrice.toStringAsFixed(2)} 元/L'
                '${r.note.isEmpty ? '' : ' · ${r.note}'}',
                style: TextStyle(color: skin.faint, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${r.liters.toStringAsFixed(1)} L',
                  style: TextStyle(
                      color: skin.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('¥${r.cost.toStringAsFixed(0)}',
                  style: TextStyle(color: skin.accent2, fontSize: 11.5)),
            ],
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, size: 17, color: skin.faint),
            onPressed: () => _deleteRecord(r),
          ),
        ],
      ),
    );
  }

  static String _date(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _ymd(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class _DueItem {
  const _DueItem({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String text;
  final Color color;
}

/// 加油录入对话框。
class _FuelDialog extends StatefulWidget {
  const _FuelDialog({this.initialOdo, required this.vehicleId});

  final double? initialOdo;
  final String vehicleId;

  @override
  State<_FuelDialog> createState() => _FuelDialogState();
}

class _FuelDialogState extends State<_FuelDialog> {
  late final TextEditingController _odo = TextEditingController(
      text: widget.initialOdo == null
          ? ''
          : widget.initialOdo!.toStringAsFixed(0));
  final TextEditingController _liters = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _full = true;
  String? _err;

  @override
  void dispose() {
    _odo.dispose();
    _liters.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final odo = double.tryParse(_odo.text.trim());
    final liters = double.tryParse(_liters.text.trim());
    final price = double.tryParse(_price.text.trim());
    if (odo == null || odo <= 0) {
      setState(() => _err = '请填写当前仪表总里程');
      return;
    }
    if (liters == null || liters <= 0) {
      setState(() => _err = '请填写本次加油升数');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _err = '请填写油价（元/L）');
      return;
    }
    Navigator.pop(
      context,
      FuelRec(
        ts: DateTime.now().millisecondsSinceEpoch,
        odo: odo,
        liters: liters,
        unitPrice: price,
        full: _full,
        note: _note.text.trim(),
        vehicleId: widget.vehicleId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('记一笔加油'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _odo,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(
                  labelText: '仪表总里程', suffixText: 'km'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _liters,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration:
                  const InputDecoration(labelText: '加油量', suffixText: 'L'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(
                  labelText: '油价', suffixText: '元/L'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('这次加满了', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                '只有加满才能闭合一段油耗区间；没加满也能记，只算花费',
                style: TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
              value: _full,
              onChanged: (v) => setState(() => _full = v),
            ),
            TextField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: '备注（可选）', hintText: '如：中石化 92#'),
            ),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
