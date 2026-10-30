import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/garage/garage.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/core/vehicle/vin.dart';
import 'package:obd_dashboard/data/obd_providers.dart';

/// 多车车库：一台手机管多辆车，各自独立车型档案、VIN、行程与加油历史。
///
/// 切换车辆会同时切换仪表盘的车型档案（档位反推 / 红区 / 告警阈值）；
/// 历史记录按 `vehicleId` 过滤，互不串。
class GarageScreen extends ConsumerStatefulWidget {
  const GarageScreen({super.key});

  @override
  ConsumerState<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends ConsumerState<GarageScreen> {
  List<GarageVehicle> _list = const [];
  List<TripRec> _trips = const [];
  String? _activeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppStore.instance.ensureGarage();
    final active = await AppStore.instance.getActiveVehicleId();
    final trips = await AppStore.instance.loadTrips();
    if (!mounted) return;
    setState(() {
      _list = list;
      _activeId = active;
      _trips = trips;
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<VinInfo?> _readVin() async {
    final obd = ref.read(obdServiceProvider);
    if (!obd.isConnected) {
      _toast('请先连接 OBD 适配器，并保持点火（ON 档）');
      return null;
    }
    final info = await obd.readVin();
    if (info == null) {
      _toast('读取失败：车辆不支持 Mode 09 02，或未点火 / 适配器断连');
    }
    return info;
  }

  Future<void> _add() async {
    final form = await showDialog<_GarageForm>(
      context: context,
      builder: (_) => _GarageEditDialog(
        title: '添加车辆',
        onReadVin: _readVin,
      ),
    );
    if (form == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final v = GarageVehicle(
      id: GarageVehicle.newId(ts),
      name: form.name,
      profileId: form.profileId,
      vin: form.vin,
      note: form.note,
      createdTs: ts,
    );
    final list = List<GarageVehicle>.from(await AppStore.instance.loadGarage())
      ..add(v);
    await AppStore.instance.saveGarage(list);
    if (_list.isEmpty) {
      await AppStore.instance.setActiveVehicleId(v.id);
      ref.read(telemetryProvider).setProfile(VehicleProfile.byId(v.profileId));
    }
    await _load();
    _toast('已添加 ${v.name}');
  }

  Future<void> _edit(GarageVehicle v) async {
    final form = await showDialog<_GarageForm>(
      context: context,
      builder: (_) => _GarageEditDialog(
        title: '编辑车辆',
        initial: v,
        onReadVin: _readVin,
      ),
    );
    if (form == null) return;
    final list = List<GarageVehicle>.from(await AppStore.instance.loadGarage());
    final i = list.indexWhere((e) => e.id == v.id);
    if (i < 0) return;
    list[i] = v.copyWith(
      name: form.name,
      profileId: form.profileId,
      vin: form.vin,
      note: form.note,
    );
    await AppStore.instance.saveGarage(list);
    if (v.id == _activeId) {
      ref
          .read(telemetryProvider)
          .setProfile(VehicleProfile.byId(form.profileId));
      if (form.vin.isNotEmpty) {
        await AppStore.instance.setLastVin(form.vin);
      }
    }
    await _load();
  }

  Future<void> _activate(GarageVehicle v) async {
    if (v.id == _activeId) return;
    await AppStore.instance.setActiveVehicleId(v.id);
    if (v.vin.isNotEmpty) await AppStore.instance.setLastVin(v.vin);
    ref.read(telemetryProvider).setProfile(VehicleProfile.byId(v.profileId));
    await _load();
    _toast('已切换到 ${v.name}');
  }

  Future<void> _delete(GarageVehicle v) async {
    if (_list.length <= 1) {
      _toast('至少保留一辆车');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('删除「${v.name}」？'),
        content: const Text('车辆的行程和加油记录会保留在本机（按车辆 id 归属），'
            '但车库中不再显示。'),
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
    final list = List<GarageVehicle>.from(await AppStore.instance.loadGarage())
      ..removeWhere((e) => e.id == v.id);
    await AppStore.instance.saveGarage(list);
    if (v.id == _activeId && list.isNotEmpty) {
      await AppStore.instance.setActiveVehicleId(list.first.id);
      ref
          .read(telemetryProvider)
          .setProfile(VehicleProfile.byId(list.first.profileId));
    }
    await _load();
  }

  _VehicleStat _statFor(GarageVehicle v) {
    final mine = _trips.where((t) =>
        t.vehicleId == v.id ||
        // 老行程没有车辆 id：归当前车辆，避免历史"消失"。
        (t.vehicleId.isEmpty && v.id == _activeId));
    var km = 0.0;
    var n = 0;
    for (final t in mine) {
      km += t.km;
      n++;
    }
    return _VehicleStat(count: n, km: km);
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('多车车库'),
        actions: [
          IconButton(
            tooltip: '添加车辆',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _add,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text(
                  '每辆车独立车型档案、VIN、行程与加油记录。切换车辆会同步切换仪表盘档位/红区/告警阈值。',
                  style: TextStyle(color: skin.dim, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 14),
                ..._list.map((v) => _vehicleCard(skin, v)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加车辆'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    foregroundColor: skin.accent,
                    side: BorderSide(color: skin.accent.withValues(alpha: 0.4)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'VIN 读取需要连接 OBD 并保持点火（ON 档）；识别不出时仍可手动选车型。'
                  '车库只存本机，不上传服务器。',
                  style: TextStyle(color: skin.faint, fontSize: 11, height: 1.6),
                ),
              ],
            ),
    );
  }

  Widget _vehicleCard(SkinDescriptor skin, GarageVehicle v) {
    final active = v.id == _activeId;
    final profile = VehicleProfile.byId(v.profileId);
    final stat = _statFor(v);
    final color = active ? skin.accent : skin.dim;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: active
            ? skin.accent.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: active
                ? skin.accent.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _activate(v),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Icon(Icons.directions_car,
                  color: color, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(v.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: skin.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (active) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: skin.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('当前',
                                style: TextStyle(
                                    color: skin.accent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.dim, fontSize: 11.5),
                    ),
                    if (v.vin.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('VIN ${v.vin}',
                          style: TextStyle(
                              color: skin.faint,
                              fontSize: 10.5,
                              fontFamily: 'monospace')),
                    ],
                    if (v.note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(v.note,
                          style: TextStyle(color: skin.faint, fontSize: 10.5)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${stat.count} 段行程 · ${stat.km.toStringAsFixed(0)} km',
                      style: TextStyle(
                          color: active ? skin.accent2 : skin.faint,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: skin.faint),
                color: skin.panel,
                onSelected: (a) {
                  if (a == 'edit') _edit(v);
                  if (a == 'delete') _delete(v);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('编辑', style: TextStyle(color: skin.ink)),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: skin.bad)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleStat {
  const _VehicleStat({required this.count, required this.km});
  final int count;
  final double km;
}

class _GarageForm {
  const _GarageForm({
    required this.name,
    required this.profileId,
    required this.vin,
    required this.note,
  });
  final String name;
  final String profileId;
  final String vin;
  final String note;
}

class _GarageEditDialog extends StatefulWidget {
  const _GarageEditDialog({
    required this.title,
    required this.onReadVin,
    this.initial,
  });

  final String title;
  final GarageVehicle? initial;
  final Future<VinInfo?> Function() onReadVin;

  @override
  State<_GarageEditDialog> createState() => _GarageEditDialogState();
}

class _GarageEditDialogState extends State<_GarageEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _vin =
      TextEditingController(text: widget.initial?.vin ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  late String _profileId = widget.initial?.profileId ??
      (VehicleProfile.presets.length > 1
          ? VehicleProfile.presets[1].id
          : VehicleProfile.presets.first.id);
  bool _reading = false;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _vin.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _readVin() async {
    setState(() => _reading = true);
    try {
      final info = await widget.onReadVin();
      if (info == null) return;
      setState(() {
        _vin.text = info.vin;
        final pid = info.matchProfileId();
        if (pid != null) _profileId = pid;
        if (_name.text.trim().isEmpty) {
          _name.text = info.year == null ? '我的车' : '${info.year} 款';
        }
      });
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _err = '给车起个名字吧');
      return;
    }
    final vin = _vin.text.trim().toUpperCase();
    if (vin.isNotEmpty && vin.length != 17) {
      setState(() => _err = 'VIN 通常是 17 位，请检查');
      return;
    }
    Navigator.pop(
      context,
      _GarageForm(
        name: name,
        profileId: _profileId,
        vin: vin,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = VehicleProfile.presets
        .where((p) => p.id != 'game')
        .toList(growable: false);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: '名称', hintText: '如：我的马 6 / 家里那台 SUV'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: presets.any((p) => p.id == _profileId)
                  ? _profileId
                  : presets.first.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '车型档案'),
              items: [
                for (final p in presets)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _profileId = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _vin,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'VIN（可选）', hintText: '17 位车架号'),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _reading ? null : _readVin,
                icon: _reading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.directions_car_filled_outlined,
                        size: 16),
                label: Text(_reading ? '读取中…' : '从车辆读取 VIN 并匹配车型'),
              ),
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: '备注（可选）', hintText: '如：92# / 家用 / 通勤'),
            ),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
