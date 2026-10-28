import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/dashboard/widgets/hex_dot.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// CYAN_HEX · 青眼六边形：六边形卡片 + 垂直转速条 + 点阵档位。
/// 移植原生 v1.9.6 的 drawCyanHex。
class CyanHexDashboard extends StatelessWidget {
  const CyanHexDashboard({
    super.key,
    required this.data,
    required this.profile,
    required this.skin,
  });

  final ObdData data;
  final VehicleProfile profile;
  final SkinDescriptor skin;

  String get _gear {
    if (data.gear < 0) return '-';
    if (data.gear == 0) return 'N';
    return data.gear.toString();
  }

  @override
  Widget build(BuildContext context) {
    return HorizonFxOverlay(
      accent: skin.accent,
      child: Container(
        decoration: BoxDecoration(color: skin.background),
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (orientation == Orientation.landscape) return _landscape();
            return _portrait();
          },
        ),
      ),
    );
  }

  // ── 横屏：上下六边形卡 + 中央档位/小数据 + 右垂直转速条 ──
  Widget _landscape() {
    return Row(
      children: [
        // 左：上下六边形卡 + 中央档位
        Expanded(
          flex: 9,
          child: Column(
            children: [
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
                  child: _topHexCard(),
                ),
              ),
              Expanded(
                flex: 2,
                child: _centerRow(),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
                  child: _bottomHexCard(),
                ),
              ),
            ],
          ),
        ),
        // 右：垂直转速条
        Expanded(
          flex: 1,
          child: _verticalRpmBar(),
        ),
      ],
    );
  }

  // ── 竖屏：上六边形卡 + 档位 + 下六边形卡 + 右转速条 ──
  Widget _portrait() {
    return Row(
      children: [
        Expanded(
          flex: 8,
          child: Column(
            children: [
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 6, 4),
                  child: _topHexCard(),
                ),
              ),
              Expanded(
                flex: 2,
                child: _centerRow(),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 6, 16),
                  child: _bottomHexCard(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: _verticalRpmBar(),
        ),
      ],
    );
  }

  // ── 中央行：档位 + 油温/进气小数据 ──
  Widget _centerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          DotGear(gear: _gear, color: skin.ink, size: 38),
          const SizedBox(width: 10),
          Text('GEAR',
              style: TextStyle(
                  color: skin.accent, fontSize: 10, letterSpacing: 2)),
          const Spacer(),
          // 油温与增压：标签/数值/单位必须一致（原版误把 boost 标成 INTAKE、
          // 单位残缺为 'b'）。补全为 °C 与 bar，行宽充足不溢出。
          _miniData('OIL', data.oilTemp?.toStringAsFixed(0), '°C'),
          const SizedBox(width: 14),
          _miniData('BOOST', data.boost?.toStringAsFixed(1), 'bar'),
        ],
      ),
    );
  }

  Widget _miniData(String label, String? value, String unit) {
    if (!data.showUnsupportedAsDashes && value == null) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            style: TextStyle(
                color: skin.accent, fontSize: 8, letterSpacing: 1)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value ?? '--',
                style: TextStyle(
                    fontFamily: 'DSEG7',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: skin.ink)),
            Text(unit, style: TextStyle(color: skin.faint, fontSize: 8)),
          ],
        ),
      ],
    );
  }

  // ── 上六边形卡：车速 ──
  Widget _topHexCard() {
    return Center(
      child: AspectRatio(
        aspectRatio: 0.866,
        child: HexPanel(
          color: skin.accent,
          fill: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SPEED',
                    style: TextStyle(
                        color: skin.accent,
                        fontSize: 10,
                        letterSpacing: 3)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    data.speed.toStringAsFixed(0).padLeft(3, '0'),
                    style: TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 52,
                      color: skin.ink,
                      shadows: [
                        Shadow(
                          color: skin.accent.withValues(alpha: 0.6),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
                Text('km/h',
                    style: TextStyle(color: skin.accent, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 下六边形卡：转速 ──
  Widget _bottomHexCard() {
    return Center(
      child: AspectRatio(
        aspectRatio: 0.866,
        child: HexPanel(
          color: skin.accent,
          fill: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('RPM',
                    style: TextStyle(
                        color: skin.accent,
                        fontSize: 10,
                        letterSpacing: 3)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    data.rpm.toString().padLeft(4, '0'),
                    style: TextStyle(
                      fontFamily: 'DSEG7',
                      fontWeight: FontWeight.bold,
                      fontSize: 46,
                      color: skin.ink,
                      shadows: [
                        Shadow(
                          color: skin.accent.withValues(alpha: 0.6),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
                Text('revolutions/min',
                    style: TextStyle(color: skin.accent, fontSize: 8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 垂直转速条 ──
  Widget _verticalRpmBar() {
    const seg = 20;
    const maxRpm = 8000;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      child: Column(
        children: [
          Text('RPM',
              style: TextStyle(
                  color: skin.accent, fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 条段（固定宽度）
                SizedBox(
                  width: 14,
                  child: Column(
                    children: List.generate(seg, (i) {
                      final v = (seg - i) / seg * maxRpm;
                      final active = data.rpm >= v;
                      final inRed = v >= profile.redlineRpm;
                      final col = active
                          ? (inRed ? skin.bad : skin.accent)
                          : (inRed
                              ? skin.bad.withValues(alpha: 0.15)
                              : skin.accent.withValues(alpha: 0.12));
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 4),
                // 刻度数字
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('8', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('6', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('4', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('2', style: TextStyle(color: skin.dim, fontSize: 8)),
                    Text('0', style: TextStyle(color: skin.dim, fontSize: 8)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
