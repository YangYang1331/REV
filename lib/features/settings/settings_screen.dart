import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/config/environment.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/alarm/alarm_settings_screen.dart';
import 'package:obd_dashboard/features/cloud/history_screen.dart';
import 'package:obd_dashboard/features/connection/connect_wizard.dart';
import 'package:obd_dashboard/features/fuel/fuel_screen.dart';
import 'package:obd_dashboard/features/garage/garage_screen.dart';
import 'package:obd_dashboard/features/maintenance/maintenance_screen.dart';
import 'package:obd_dashboard/features/settings/about_screen.dart';
import 'package:obd_dashboard/features/settings/appearance_screen.dart';
import 'package:obd_dashboard/features/settings/cloud_account_screen.dart';
import 'package:obd_dashboard/features/settings/settings_common.dart';
import 'package:obd_dashboard/features/settings/vehicle_settings_screen.dart';

/// 设置总入口。
///
/// 以前所有开关和页面堆在一个长列表里，找东西要翻很久；
/// 现在按「外观 / 车辆 / 提醒 / 云端 / 关于」拆成 5 个分组入口。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final t = ref.watch(telemetryProvider);
    final auth = ref.watch(authProvider);
    final cloud = ref.watch(cloudServiceProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          _statusCard(skin.label, t.profile.name, auth.isLoggedIn,
              auth.username),
          const SettingsHeader('外观与显示'),
          SettingsTile(
            icon: Icons.palette_outlined,
            title: '皮肤与显示',
            subtitle: '当前皮肤：${skin.label} · 动效 / 常亮 / 音效声浪',
            onTap: () => _open(const AppearanceScreen()),
          ),
          const SettingsHeader('车辆'),
          SettingsTile(
            icon: Icons.garage_outlined,
            title: '多车车库',
            subtitle: '多辆车独立档案 / VIN 自动识别 / 每车独立历史',
            onTap: () => _open(const GarageScreen()),
          ),
          SettingsTile(
            icon: Icons.directions_car_outlined,
            title: '车辆与校准',
            subtitle: '车型档案：${t.profile.name} · VIN 识别 / 速度校准',
            onTap: () => _open(const VehicleSettingsScreen()),
          ),
          SettingsTile(
            icon: Icons.route_outlined,
            title: '首次连接向导',
            subtitle: '选方式 → 选设备 → 连接 → 读 VIN 自动匹配车型',
            onTap: () => _open(const ConnectWizard()),
          ),
          const SettingsHeader('提醒与养护'),
          SettingsTile(
            icon: Icons.notifications_active_outlined,
            title: '报警与语音',
            subtitle: '水温 / 油温 / 电压 / 超速阈值，语音播报与提示音',
            onTap: () => _open(const AlarmSettingsScreen()),
          ),
          SettingsTile(
            icon: Icons.build_circle_outlined,
            title: '保养提醒',
            subtitle: '机油 / 轮胎 / 年检 / 保险按里程与日期倒计时',
            onTap: () => _open(const MaintenanceScreen()),
          ),
          SettingsTile(
            icon: Icons.local_gas_station_outlined,
            title: '油耗与账本',
            subtitle: '加油记录 / 长期油耗 / 养车花费',
            onTap: () => _open(const FuelScreen()),
          ),
          const SettingsHeader('云端与账号'),
          SettingsTile(
            icon: Icons.show_chart,
            title: '云端历史趋势',
            subtitle: '查看服务器记录的水温 / 油温 / 电压曲线',
            onTap: () => _open(const HistoryScreen()),
          ),
          SettingsTile(
            icon: Icons.cloud_outlined,
            color: const Color(0xFFFF6B3D),
            title: '账号与云端',
            subtitle: auth.isLoggedIn
                ? '已登录：${auth.username} · ${cloud.endpoint}'
                : '未登录 · 服务器地址 / 上报状态 / 隐私开关',
            onTap: () => _open(const CloudAccountScreen()),
          ),
          const SettingsHeader('关于'),
          SettingsTile(
            icon: Icons.info_outline,
            title: '关于与更新',
            subtitle: 'v${AppEnvironment.version} · 检查更新 / 扩展实验室 / 运行日志',
            onTap: () => _open(const AboutScreen()),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  /// 顶部状态卡：一眼看到皮肤 / 车型 / 账号 / 服务器。
  Widget _statusCard(
    String skinName,
    String vehicleName,
    bool loggedIn,
    String? username,
  ) {
    const ok = Color(0xFF27D6E6);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前配置',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      letterSpacing: 1),
                ),
                const SizedBox(height: 6),
                Text(
                  '$skinName · $vehicleName',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  loggedIn ? '账号 $username · 云端同步中' : '未登录 · 仅本地使用',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(
            loggedIn ? Icons.cloud_done : Icons.cloud_off,
            color: loggedIn ? ok : const Color(0xFFFF6B3D),
            size: 22,
          ),
        ],
      ),
    );
  }
}
