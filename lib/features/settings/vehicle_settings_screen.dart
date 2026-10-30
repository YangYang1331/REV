import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/settings/settings_common.dart';
import 'package:obd_dashboard/features/settings/speed_calibration_screen.dart';

/// 车辆与校准：车型档案、VIN 自动识别、速度系数。
class VehicleSettingsScreen extends ConsumerStatefulWidget {
  const VehicleSettingsScreen({super.key});

  @override
  ConsumerState<VehicleSettingsScreen> createState() =>
      _VehicleSettingsScreenState();
}

class _VehicleSettingsScreenState extends ConsumerState<VehicleSettingsScreen> {
  /// 最近一次成功读取的 VIN（仅本地展示，用于判断是否已自动匹配过）。
  String? _vin;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVin());
  }

  Future<void> _loadVin() async {
    try {
      final v = await AppStore.instance.getLastVin();
      if (mounted && v != null && v.isNotEmpty) setState(() => _vin = v);
    } catch (_) {}
  }

  /// 从车辆读取 Mode 09 02 车架号，按 VIN 匹配内置车型（识别不出就保持手选）。
  Future<void> _readVin() async {
    final obd = ref.read(obdServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (!obd.isConnected) {
      messenger.showSnackBar(const SnackBar(
          content: Text('请先在连接页连上 OBD 适配器，并保持车辆点火（ON 档）')));
      return;
    }
    messenger.showSnackBar(const SnackBar(
        content: Text('正在读取车架号（约 3–8 秒）…'),
        duration: Duration(seconds: 2)));
    final info = await obd.readVin();
    if (!mounted) return;
    if (info == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('读取失败：车辆不支持 Mode 09 02，或未点火 / 适配器断连')));
      return;
    }
    await AppStore.instance.setLastVin(info.vin);
    final pid = info.matchProfileId();
    if (pid != null) {
      ref.read(telemetryProvider).setProfile(VehicleProfile.byId(pid));
      final name = VehicleProfile.byId(pid).name;
      messenger.showSnackBar(SnackBar(
          content: Text('已识别 ${info.summary} → $name'),
          duration: const Duration(seconds: 4)));
    } else {
      messenger.showSnackBar(SnackBar(
          content: Text('读到 ${info.summary}，暂无法自动匹配车型，请手动选择'),
          duration: const Duration(seconds: 4)));
    }
    setState(() => _vin = info.vin);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider);
    return SettingsScaffold(
      title: '车辆与校准',
      body: ListView(
        children: [
          const SettingsHeader('车型档案（决定档位反推 / 红区 / 告警阈值）'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DropdownButton<String>(
              isExpanded: true,
              value: t.profile.id,
              dropdownColor: const Color(0xFF11161D),
              items: VehicleProfile.presets
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  ref
                      .read(telemetryProvider)
                      .setProfile(VehicleProfile.byId(v));
                  setState(() {});
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              t.profile.note.isEmpty
                  ? '档位按车速分段估算；红区 ${t.profile.redlineRpm} RPM，最高 ${t.profile.maxGear} 挡。'
                  : t.profile.note,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 12, height: 1.5),
            ),
          ),
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: const Icon(Icons.qr_code_scanner, color: kSettingsAccent),
            title:
                const Text('VIN 自动识别车型', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _vin == null
                  ? '连上适配器后一键读取车架号，按 VIN 自动选好车型档案'
                  : '上次读取：$_vin（识别不准可手动改上方下拉）',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: const Icon(Icons.play_circle_outline,
                color: kSettingsAccent, size: 22),
            onTap: _readVin,
          ),
          const SettingsHeader('仪表校准'),
          SettingsTile(
            icon: Icons.speed,
            title: '速度校准',
            subtitle: '当前系数 ${t.speedFactor.toStringAsFixed(2)}（与实际车速有偏差时使用）',
            onTap: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SpeedCalibrationScreen()));
              setState(() {});
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
