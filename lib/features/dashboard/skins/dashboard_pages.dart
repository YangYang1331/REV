import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/eco_tips.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// 仪表盘内滑动页面：经济页 + 数据页。
/// 配合 [PageView] 在仪表盘内左右滑动切换。

/// 经济驾驶页：油耗 / 里程 / 水温 / 燃油。
class EconomyPage extends StatelessWidget {
  const EconomyPage({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });

  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final landscape = orientation == Orientation.landscape;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: landscape ? 28 : 20,
            vertical: landscape ? 16 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (landscape)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _mainFuel()),
                      const SizedBox(width: 16),
                      Expanded(child: _fuelStats()),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      _mainFuel(),
                      const SizedBox(height: 14),
                      Expanded(child: _fuelStats()),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              EcoTipBar(data: data, skin: skin),
            ],
          ),
        );
      },
    );
  }

  // 主油耗大数字
  Widget _mainFuel() {
    final l100 = data.fuelL100;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: skin.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('瞬时油耗',
              style: TextStyle(
                  color: skin.dim, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  l100?.toStringAsFixed(1) ??
                      (data.fuelLph?.toStringAsFixed(1) ?? '--'),
                  style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 52,
                    color: skin.accent,
                    shadows: [
                      Shadow(
                        color: skin.accent.withValues(alpha: 0.5),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(l100 != null ? 'L/100km' : 'L/h',
                    style: TextStyle(color: skin.dim, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 燃油统计
  Widget _fuelStats() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _statTile(
                  '平均油耗',
                  data.tripL100?.toStringAsFixed(1),
                  'L/100km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  '本次里程',
                  data.tripKm.toStringAsFixed(1),
                  'km',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _statTile(
                  '行程时间',
                  _formatTime(data.tripSec.toInt()),
                  '',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  '燃油液位',
                  data.fuelLevel?.toStringAsFixed(0),
                  '%',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _statTile(
            '平均车速',
            data.tripAvgSpeed.toStringAsFixed(0),
            'km/h',
          ),
        ),
      ],
    );
  }

  Widget _statTile(String label, String? value, String unit) {
    if (!data.showUnsupportedAsDashes && value == null) {
      return _emptyTile(label);
    }
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
          Text(label,
              style: TextStyle(color: skin.dim, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value ?? '--',
                    style: TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 26,
                      color: skin.ink,
                    )),
                if (unit.isNotEmpty)
                  Text(' $unit',
                      style: TextStyle(color: skin.faint, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTile(String label) {
    return Container(
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.panelStroke),
      ),
      child: Center(
        child: Text(label, style: TextStyle(color: skin.faint, fontSize: 12)),
      ),
    );
  }

  static String _formatTime(int? sec) {
    if (sec == null) return '--';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// 关键数据一览页：车速/档位 + 核心数据流。
class DataGlancePage extends StatelessWidget {
  const DataGlancePage({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });

  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final landscape = orientation == Orientation.landscape;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: landscape ? 28 : 20,
            vertical: landscape ? 14 : 18,
          ),
          child: Column(
            children: [
              // 顶部：车速/转速/档位
              _topBar(landscape),
              SizedBox(height: landscape ? 12 : 14),
              // 数据流
              Expanded(child: _dataGrid(landscape)),
            ],
          ),
        );
      },
    );
  }

  Widget _topBar(bool landscape) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: skin.panelStroke),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _topItem('车速', data.speed.toStringAsFixed(0), 'km/h',
                  skin.accent),
              _divider(),
              _topItem('转速', data.rpm.toString(), 'rpm', skin.ink),
              _divider(),
              _topItem(
                  '档位',
                  data.gear < 0 ? '-' : data.gear == 0 ? 'N' : '${data.gear}',
                  '',
                  skin.accent2),
            ],
          ),
          if (data.isGpsEstimated) ...[
            const SizedBox(height: 6),
            Text('转速 / 档位为 GPS 齿比估算',
                style: TextStyle(
                    color: const Color(0xFF27D6E6),
                    fontSize: 10,
                    letterSpacing: 1)),
          ],
        ],
      ),
    );
  }

  Widget _topItem(String label, String value, String unit, Color color) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                  fontFamily: 'DSEG7',
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                  color: color,
                )),
            if (unit.isNotEmpty)
              Text(' $unit',
                  style: TextStyle(color: skin.faint, fontSize: 10)),
          ],
        ),
        Text(label,
            style: TextStyle(color: skin.dim, fontSize: 10, letterSpacing: 1)),
      ],
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 34,
      color: skin.panelStroke,
    );
  }

  Widget _dataGrid(bool landscape) {
    final items = <_GlanceItem>[
      _GlanceItem('MAF', data.maf?.toStringAsFixed(1), 'g/s'),
      _GlanceItem('负荷', data.load?.toStringAsFixed(0), '%'),
      _GlanceItem('节气门', data.throttle?.toStringAsFixed(0), '%'),
      _GlanceItem('水温', data.coolant?.toStringAsFixed(0), '°C'),
      _GlanceItem('进气', data.intakeTemp?.toStringAsFixed(0), '°C'),
      _GlanceItem('电压', data.voltage?.toStringAsFixed(1), 'V'),
      _GlanceItem('增压', data.boost?.toStringAsFixed(1), 'bar'),
      _GlanceItem('点火', data.ignAdv?.toStringAsFixed(1), '°'),
    ];
    final shown = data.isDemo
        ? items
        : items.where((e) => e.value != null).toList();

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: landscape ? 4 : 2,
        childAspectRatio: landscape ? 2.0 : 2.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final it = shown[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: skin.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.panelStroke),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(it.label,
                  style: TextStyle(color: skin.dim, fontSize: 12)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(it.value ?? '--',
                      style: TextStyle(
                        fontFamily: 'DSEG7',
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: skin.ink,
                      )),
                  Text(' ${it.unit}',
                      style: TextStyle(color: skin.faint, fontSize: 9)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlanceItem {
  _GlanceItem(this.label, this.value, this.unit);
  final String label;
  final String? value;
  final String unit;
}
