import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 自定义磁贴看板：长按磁贴拖拽排序，右上角“模块”自由增删指标。
/// 顺序与可见模块均持久化到 AppStore；不改动任何现有皮肤渲染。
class TilesBoardScreen extends ConsumerStatefulWidget {
  const TilesBoardScreen({super.key});

  @override
  ConsumerState<TilesBoardScreen> createState() => _TilesBoardScreenState();
}

class _TilesBoardScreenState extends ConsumerState<TilesBoardScreen> {
  /// 全量偏好顺序（含未显示的模块）。
  List<String> _order = List.of(AppStore.defaultTileModules);

  /// 当前可见模块集合。
  Set<String> _modules = List.of(AppStore.defaultTileModules).toSet();

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await AppStore.instance.getTileOrder();
    final mods = await AppStore.instance.getTileModules();
    if (!mounted) return;
    setState(() {
      _order = order;
      _modules = mods.toSet();
      _loaded = true;
    });
  }

  /// 实际展示顺序：偏好顺序 ∩ 可见集合，再补上“可见但不在顺序里”的模块。
  List<String> get _visible {
    final list = _order.where(_modules.contains).toList();
    for (final id in _modules) {
      if (!list.contains(id)) list.add(id);
    }
    return list;
  }

  Future<void> _persist() async {
    await AppStore.instance.setTileOrder(_order);
    await AppStore.instance.setTileModules(_modules.toList());
  }

  void _onReorder(int oldIndex, int newIndex) {
    final visible = _visible;
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final id = visible.removeAt(oldIndex);
    visible.insert(newIndex.clamp(0, visible.length), id);
    // 重排可见部分，隐藏的模块按默认顺序追加在后
    final rest =
        AppStore.defaultTileModules.where((e) => !_modules.contains(e));
    setState(() => _order = [...visible, ...rest]);
    _persist();
  }

  Future<void> _pickModules() async {
    Set<String>? result;
    await showDialog<void>(
      context: context,
      builder: (c) {
        Set<String> temp = Set.of(_modules);
        return StatefulBuilder(
          builder: (c, setDialog) {
            return AlertDialog(
              title: const Text('选择显示模块'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: AppStore.defaultTileModules.map((id) {
                    final def = _TileCatalog.byId(id);
                    final checked = temp.contains(id);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      title: Text(def?.label ?? id),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setDialog(() {
                        if (v == true) {
                          temp.add(id);
                        } else {
                          temp.remove(id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    result = temp;
                    Navigator.pop(c);
                  },
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) return;
    setState(() => _modules = result!);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    final d = t.current;
    final skin = ref.watch(skinProvider);
    final visible = _visible;

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('磁贴看板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize_outlined),
            tooltip: '模块选择',
            onPressed: _pickModules,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Icon(Icons.open_with, size: 15, color: skin.faint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('长按磁贴拖拽排序 · 点击右上角图标增删模块',
                      style: TextStyle(color: skin.faint, fontSize: 11)),
                ),
                if (d.isDemo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: skin.warn.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('DEMO',
                        style: TextStyle(
                            color: skin.warn,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(
                        child: Text('未选择任何模块，点右上角添加',
                            style: TextStyle(color: skin.faint, fontSize: 13)),
                      )
                    : OrientationBuilder(
                        builder: (context, o) {
                          final landscape = o == Orientation.landscape;
                          return ReorderableGridView.builder(
                            padding: const EdgeInsets.all(14),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: landscape ? 3 : 2,
                              childAspectRatio: landscape ? 2.6 : 2.1,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: visible.length,
                            onReorder: _onReorder,
                            itemBuilder: (context, i) {
                              final id = visible[i];
                              return _TileCard(
                                key: ValueKey('tile-$id'),
                                id: id,
                                data: d,
                                skin: skin,
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// 单个指标磁贴：标签 + 实时数值 + 单位，皮肤令牌配色。
class _TileCard extends StatelessWidget {
  const _TileCard({
    super.key,
    required this.id,
    required this.data,
    required this.skin,
  });

  final String id;
  final ObdData data;
  final SkinDescriptor skin;

  @override
  Widget build(BuildContext context) {
    final def = _TileCatalog.byId(id);
    if (def == null) return const SizedBox.shrink();
    final text = def.text(data);
    final has = text != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(def.label,
              style: TextStyle(
                  color: skin.dim, fontSize: 11, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    has ? text : '--',
                    style: TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 30,
                      color: has ? skin.ink : skin.faint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(def.unit(data),
                  style: TextStyle(color: skin.faint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 磁贴模块定义表（与 AppStore.defaultTileModules 的 id 一一对应）。
class _TileDef {
  const _TileDef({
    required this.id,
    required this.label,
    required this.text,
    required this.unit,
  });

  final String id;
  final String label;
  final String? Function(ObdData d) text;
  final String Function(ObdData d) unit;
}

class _TileCatalog {
  static final List<_TileDef> _all = [
    _TileDef(
      id: 'speed',
      label: '车速',
      text: (d) => d.speed.toStringAsFixed(0),
      unit: (_) => 'km/h',
    ),
    _TileDef(
      id: 'rpm',
      label: '转速',
      text: (d) => '${d.rpm}',
      unit: (_) => 'rpm',
    ),
    _TileDef(
      id: 'gear',
      label: '档位',
      text: (d) => d.gear <= 0 ? 'N' : '${d.gear}',
      unit: (_) => '挡',
    ),
    _TileDef(
      id: 'coolant',
      label: '水温',
      text: (d) => d.coolant?.toStringAsFixed(0),
      unit: (_) => '°C',
    ),
    _TileDef(
      id: 'voltage',
      label: '电压',
      text: (d) => d.voltage?.toStringAsFixed(1),
      unit: (_) => 'V',
    ),
    _TileDef(
      id: 'boost',
      label: '增压',
      text: (d) => d.boost?.toStringAsFixed(2),
      unit: (_) => 'bar',
    ),
    _TileDef(
      id: 'load',
      label: '负荷',
      text: (d) => d.load?.toStringAsFixed(0),
      unit: (_) => '%',
    ),
    _TileDef(
      id: 'throttle',
      label: '节气门',
      text: (d) => d.throttle?.toStringAsFixed(0),
      unit: (_) => '%',
    ),
    _TileDef(
      id: 'maf',
      label: '空气流量',
      text: (d) => d.maf?.toStringAsFixed(1),
      unit: (_) => 'g/s',
    ),
    _TileDef(
      id: 'fuelRate',
      label: '油耗',
      text: (d) =>
          d.fuelL100?.toStringAsFixed(1) ?? d.fuelLph?.toStringAsFixed(1),
      unit: (d) => d.fuelL100 != null ? 'L/100km' : 'L/h',
    ),
    _TileDef(
      id: 'fuelLevel',
      label: '油位',
      text: (d) => d.fuelLevel?.toStringAsFixed(0),
      unit: (_) => '%',
    ),
    _TileDef(
      id: 'intakeTemp',
      label: '进气温度',
      text: (d) => d.intakeTemp?.toStringAsFixed(0),
      unit: (_) => '°C',
    ),
    _TileDef(
      id: 'tripKm',
      label: '行程里程',
      text: (d) => d.tripKm.toStringAsFixed(1),
      unit: (_) => 'km',
    ),
    _TileDef(
      id: 'tripFuel',
      label: '行程耗油',
      text: (d) => d.tripFuel.toStringAsFixed(2),
      unit: (_) => 'L',
    ),
  ];

  static _TileDef? byId(String id) {
    for (final def in _all) {
      if (def.id == id) return def;
    }
    return null;
  }
}
