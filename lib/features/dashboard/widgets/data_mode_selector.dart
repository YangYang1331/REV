import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/auth/auth_screen.dart';
import 'package:obd_dashboard/services/gps_speed_service.dart';

/// 数据源模式选择器：演示模式 DEMO / 实车连接 OBD。
/// 选 demo：先断开 OBD 再切本地模拟；选 real：切真实模式并触发 [onEnterReal]
/// 让调用方进入扫描/连接流程。演示同步开关需登录才生效。
class DataModeSelector extends ConsumerWidget {
  const DataModeSelector({
    super.key,
    this.onEnterReal,
    this.onEnterUsb,
    this.onEnterWifi,
  });

  /// 选中"实车连接(蓝牙 BLE)"后回调（由连接页进入扫描连接）。
  final VoidCallback? onEnterReal;

  /// 选中"USB 有线 OBD"后回调（由连接页进入 USB 设备列表）。
  final VoidCallback? onEnterUsb;

  /// 选中"WiFi OBD"后回调（由连接页发起 TCP 连接）。
  final VoidCallback? onEnterWifi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(skinProvider);
    final tele = ref.watch(telemetryProvider);
    final auth = ref.watch(authProvider);
    final accent = skin.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeCard(
          selected: tele.isDemoMode,
          accent: accent,
          icon: Icons.science_outlined,
          title: '演示模式 DEMO',
          subtitle: '纯本地模拟，不连蓝牙',
          onTap: () async {
            try {
              final obd = ref.read(obdServiceProvider);
              await obd.disconnect();
              await ref.read(telemetryProvider).selectMode('demo');
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('切换演示模式失败，请重试')),
                );
              }
            }
          },
        ),
        const SizedBox(height: 12),
        _ModeCard(
          selected: tele.isRealMode,
          accent: accent,
          icon: Icons.bluetooth_drive,
          title: '实车连接 OBD（蓝牙 BLE）',
          subtitle: '连接 BLE ELM327 看真实数据',
          onTap: () async {
            try {
              await ref.read(telemetryProvider).selectMode('real');
              onEnterReal?.call();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('进入实车模式失败，请重试')),
                );
              }
            }
          },
        ),
        const SizedBox(height: 12),
        _ModeCard(
          selected: tele.isRealMode,
          accent: accent,
          icon: Icons.usb,
          title: 'USB 有线 OBD',
          subtitle: 'OTG 转接头直连 ELM327（CH340/CP210x/FTDI）',
          onTap: () async {
            try {
              await ref.read(telemetryProvider).selectMode('real');
              onEnterUsb?.call();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('进入 USB 模式失败，请重试')),
                );
              }
            }
          },
        ),
        const SizedBox(height: 12),
        _ModeCard(
          selected: tele.isRealMode,
          accent: accent,
          icon: Icons.wifi,
          title: 'WiFi OBD（TCP ELM327）',
          subtitle: '连盒子热点后直连 192.168.0.10:35000',
          onTap: () async {
            try {
              await ref.read(telemetryProvider).selectMode('real');
              onEnterWifi?.call();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('进入 WiFi OBD 模式失败，请重试')),
                );
              }
            }
          },
        ),
        const SizedBox(height: 12),
        _ModeCard(
          selected: tele.isGpsMode,
          accent: accent,
          icon: Icons.speed,
          title: 'GPS 速度模式（无 OBD 快乐表）',
          subtitle: '纯手机 GPS，无需 OBD/可离线，转速档位为估算',
          onTap: () async {
            try {
              final obd = ref.read(obdServiceProvider);
              await obd.disconnect();
              final st =
                  await ref.read(telemetryProvider).selectMode('gps');
              if (!context.mounted) return;
              final msg = switch (st) {
                GpsPermissionStatus.ok => 'GPS 速度模式已开启',
                GpsPermissionStatus.serviceDisabled =>
                  '定位服务未开启，请在系统设置中打开定位后重试',
                GpsPermissionStatus.denied =>
                  '定位权限被拒绝，请在应用设置中允许定位',
                GpsPermissionStatus.deniedForever =>
                  '定位权限被永久拒绝，请前往应用设置手动允许定位',
              };
              final needSettings = st != GpsPermissionStatus.ok;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  action: needSettings
                      ? SnackBarAction(
                          label: '去设置',
                          textColor: accent,
                          onPressed: () => openAppSettings(),
                        )
                      : null,
                ),
              );
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('进入 GPS 模式失败，请重试')),
                );
              }
            }
          },
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.white.withOpacity(0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          child: SwitchListTile(
            secondary: Icon(Icons.cloud_upload_outlined, color: accent),
            title: const Text('同步演示数据到看板',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(
                auth.isLoggedIn ? '已开启：看板标注为"演示"（仅自己可见）' : '登录后自动同步到看板',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            value: tele.demoReport,
            activeColor: accent,
            onChanged: (v) {
              if (v && !auth.isLoggedIn) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('需先登录，才能把演示数据同步到看板'),
                    action: SnackBarAction(
                      label: '去登录',
                      textColor: accent,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      ),
                    ),
                  ),
                );
                return;
              }
              try {
                ref.read(telemetryProvider).setDemoReport(v);
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置同步失败，请重试')),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : Colors.white.withOpacity(0.1),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? accent : Colors.white54, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? accent : Colors.white24,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
