import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:obd_dashboard/core/config/environment.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/skin/skin_registry.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/core/vehicle/engine_pack_mapping.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/auth/auth_screen.dart';
import 'package:obd_dashboard/features/alarm/alarm_settings_screen.dart';
import 'package:obd_dashboard/features/cloud/history_screen.dart';
import 'package:obd_dashboard/features/connection/connect_wizard.dart';
import 'package:obd_dashboard/features/lab/lab_screen.dart';
import 'package:obd_dashboard/features/maintenance/maintenance_screen.dart';
import 'package:obd_dashboard/features/privacy/privacy_screen.dart';
import 'package:obd_dashboard/features/settings/engine_pack_screen.dart';
import 'package:obd_dashboard/features/settings/speed_calibration_screen.dart';
import 'package:obd_dashboard/services/cloud_service.dart';
import 'package:obd_dashboard/services/crash_guard.dart';
import 'package:obd_dashboard/services/screen_awake.dart';
import 'package:obd_dashboard/services/engine_sound_service.dart';
import 'package:obd_dashboard/services/sound_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ScreenAwake _awake = ScreenAwake();

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
    final skin = ref.watch(skinProvider);
    final t = ref.watch(telemetryProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('皮肤与设置'),
      ),
      body: ListView(
        children: [
          _header('仪表盘皮肤'),
          ...SkinRegistry.all.map((s) => RadioListTile<String>(
                activeColor: s.accent,
                title: Text(s.label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(_skinDesc(s.id),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
                value: s.id,
                groupValue: skin.id,
                onChanged: (v) => ref.read(skinProvider.notifier).select(v!),
              )),
          _header('车型档案（决定档位反推 / 红区 / 告警阈值）'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              t.profile.note.isEmpty
                  ? '档位按车速分段估算；红区 ${t.profile.redlineRpm} RPM，最高 ${t.profile.maxGear} 挡。'
                  : t.profile.note,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 12, height: 1.5),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner, color: Color(0xFF27D6E6)),
            title:
                const Text('VIN 自动识别车型', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _vin == null
                  ? '连上适配器后一键读取车架号，按 VIN 自动选好车型档案'
                  : '上次读取：$_vin（识别不准可手动改上方下拉）',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: const Icon(Icons.play_circle_outline,
                color: Color(0xFF27D6E6), size: 22),
            onTap: _readVin,
          ),
          _header('连接与提醒'),
          ListTile(
            leading:
                const Icon(Icons.route_outlined, color: Color(0xFF27D6E6)),
            title: const Text('首次连接向导', style: TextStyle(color: Colors.white)),
            subtitle: const Text('选方式 → 选设备 → 连接 → 读 VIN 自动匹配车型',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ConnectWizard())),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined,
                color: Color(0xFF27D6E6)),
            title: const Text('报警与语音', style: TextStyle(color: Colors.white)),
            subtitle: const Text('水温/油温/电压/超速阈值，语音播报与提示音',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AlarmSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.build_circle_outlined,
                color: Color(0xFF27D6E6)),
            title: const Text('保养提醒', style: TextStyle(color: Colors.white)),
            subtitle: const Text('机油 / 轮胎 / 年检按里程与日期倒计时',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MaintenanceScreen())),
          ),
          ListTile(
            leading:
                const Icon(Icons.show_chart, color: Color(0xFF27D6E6)),
            title: const Text('云端历史趋势', style: TextStyle(color: Colors.white)),
            subtitle: const Text('查看服务器记录的水温/油温/电压曲线',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          _header('校准'),
          ListTile(
            leading: const Icon(Icons.speed, color: Color(0xFF27D6E6)),
            title: const Text('速度校准', style: TextStyle(color: Colors.white)),
            subtitle: Text('当前系数 ${t.speedFactor.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SpeedCalibrationScreen()));
              setState(() {});
            },
          ),
          _header('显示'),
          SwitchListTile(
            title: const Text('危险红屏告警', style: TextStyle(color: Colors.white)),
            subtitle: const Text('水温过高 / 转速越红区时全屏闪烁',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            value: t.redFlash,
            activeColor: const Color(0xFF27D6E6),
            onChanged: (v) => t.setRedFlash(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome, color: Color(0xFF27D6E6)),
            title: const Text('地平线动效', style: TextStyle(color: Colors.white)),
            subtitle: const Text('开屏多表自检扫表 / 青色背光 / 警示灯逐亮 / 进仪表盘一次性光扫',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: AppStore.horizonFx,
            activeColor: const Color(0xFF27D6E6),
            onChanged: (v) {
              AppStore.instance.setHorizonFx(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bolt, color: Color(0xFF27D6E6)),
            title: const Text('开屏动画', style: TextStyle(color: Colors.white)),
            subtitle: const Text('默认开：通电仪表自检扫针 → REV 定版自绘序列；关闭则直接进入仪表盘',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: AppStore.videoSplash,
            activeColor: const Color(0xFF27D6E6),
            onChanged: (v) {
              AppStore.instance.setVideoSplash(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('保持屏幕常亮', style: TextStyle(color: Colors.white)),
            value: _awake.enabled,
            activeColor: const Color(0xFF27D6E6),
            onChanged: (v) => _awake.setEnabled(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration, color: Color(0xFF27D6E6)),
            title: const Text('音效与触感反馈', style: TextStyle(color: Colors.white)),
            subtitle: const Text('连接成功提示音 / 告警震动提示',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: SoundService.instance.enabled,
            activeColor: const Color(0xFF27D6E6),
            onChanged: (v) {
              SoundService.instance.setEnabled(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary:
                const Icon(Icons.surround_sound, color: Color(0xFFFF6B3D)),
            title: const Text('模拟声浪（随转速）',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('排气脉冲音高只随转速变化，负荷与挡位只改音色；进仪表盘才发声，默认关闭',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: EngineSoundService.instance.enabled,
            activeColor: const Color(0xFF27D6E6),
            onChanged: (v) async {
              await EngineSoundService.instance.setEnabled(v);
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note, color: Color(0xFFFF6B3D)),
            title: const Text('引擎声浪引擎', style: TextStyle(color: Colors.white)),
            subtitle: Text(
                '当前：${EngineSoundService.instance.packId}（实时合成 / 采样包可选）',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EnginePackScreen()));
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.high_quality, color: Color(0xFFFF6B3D)),
            title: const Text('采样音质', style: TextStyle(color: Colors.white)),
            subtitle: Text(
                '当前：${_qualityLabel(EngineSoundService.instance.audioQuality)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => _pickAudioQuality(context),
          ),
          _header('隐私与数据'),
          Consumer(builder: (context, wref, _) {
            final cloud = wref.watch(cloudServiceProvider);
            return ListTile(
              leading: const Icon(Icons.shield_outlined, color: Color(0xFF27D6E6)),
              title: const Text('隐私与数据说明',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                '${cloud.cloudUpload ? '上传车辆数据' : '仅本地使用（不上传）'}'
                ' · ${cloud.gpsUpload ? '包含位置' : '不含位置'}'
                ' · 可随时查看/修改',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PrivacyScreen(gate: false)));
                if (mounted) setState(() {});
              },
            );
          }),
          _header('账号 · 车队看板'),
          Consumer(builder: (context, wref, _) {
            final auth = wref.watch(authProvider);
            if (!auth.isLoggedIn) {
              return ListTile(
                leading: const Icon(Icons.account_circle_outlined,
                    color: Color(0xFFFF6B3D)),
                title: const Text('未登录',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('登录或注册后，车辆数据才会上报到你的专属看板',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing:
                    const Icon(Icons.chevron_right, color: Colors.white24),
                onTap: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AuthScreen()));
                  if (mounted) setState(() {});
                },
              );
            }
            final isAdmin = auth.isAdmin;
            return ListTile(
              leading: Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.account_circle,
                color: const Color(0xFFFF6B3D),
              ),
              title: Text(auth.username ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text(isAdmin ? '管理员 · 可查看全部车辆' : '普通用户 · 仅查看自己的车辆',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              trailing: TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF11161D),
                      title: const Text('退出登录？',
                          style: TextStyle(color: Colors.white)),
                      content: const Text('退出后车辆数据将停止上报到看板。',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('退出',
                                style: TextStyle(color: Color(0xFFFF6B3D)))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      await auth.logout();
                    } catch (_) {
                      // 本地状态已清除即可，忽略网络异常
                    }
                    if (mounted) setState(() {});
                  }
                },
                child: const Text('退出登录'),
              ),
            );
          }),
          _header('云端 · 车队看板'),
          Consumer(builder: (context, wref, _) {
            final cloud = wref.watch(cloudServiceProvider);
            return ListTile(
              leading:
                  const Icon(Icons.cloud_outlined, color: Color(0xFF27D6E6)),
              title:
                  const Text('云服务器地址', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                  cloud.needsUserServer
                      ? '未配置：请填写你自己部署的服务器地址（留空则不上报、不检查更新）'
                      : (cloud.endpointHealed
                          ? '${cloud.endpoint}\n已自动修正地址（原先多写了路径）'
                          : cloud.endpoint),
                  style: TextStyle(
                      color: cloud.needsUserServer
                          ? Color(0xFFFFB4A8)
                          : Colors.white38,
                      fontSize: 11)),
              trailing: const Icon(Icons.edit, color: Colors.white24, size: 18),
              onTap: () => _editEndpoint(cloud),
            );
          }),
          Consumer(builder: (context, wref, _) {
            final cloud = wref.watch(cloudServiceProvider);
            if (!cloud.isPlaintextPublic) return const SizedBox.shrink();
            return ListTile(
              leading: const Icon(Icons.gpp_maybe, color: Color(0xFFFF6B3D)),
              title: const Text('当前使用明文 HTTP 直连 IP',
                  style: TextStyle(color: Color(0xFFFFB4A8), fontSize: 13)),
              subtitle: const Text(
                  '数据在网络上是未加密的。建议给服务器配置域名 + HTTPS 证书后改用域名地址。',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              dense: true,
            );
          }),
          Consumer(builder: (context, wref, _) {
            final cloud = wref.watch(cloudServiceProvider);
            final auth = wref.watch(authProvider);
            wref.watch(telemetryProvider); // 随遥测刷新，状态实时可见
            final ok = cloud.lastOkAt;
            final err = cloud.lastError;
            final String state;
            if (!auth.isLoggedIn) {
              state = '未登录：看板收不到数据，请先登录账号';
            } else if (err != null) {
              state = '上报失败：$err';
            } else if (ok == null) {
              state = '已登录，等待首帧上报…';
            } else {
              final sec = DateTime.now().difference(ok).inSeconds;
              state = '上报正常 · 最近一次 ${sec}s 前 · 设备 ${cloud.deviceId}';
            }
            return ListTile(
              leading: Icon(
                err != null || !auth.isLoggedIn
                    ? Icons.cloud_off
                    : Icons.cloud_done,
                color: err != null || !auth.isLoggedIn
                    ? const Color(0xFFFF6B3D)
                    : const Color(0xFF27D6E6),
              ),
              title: const Text('上报状态', style: TextStyle(color: Colors.white)),
              subtitle: Text(state,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (!auth.isLoggedIn) {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AuthScreen()));
                    return;
                  }
                  messenger.showSnackBar(const SnackBar(
                      content: Text('正在测试上报…'),
                      duration: Duration(seconds: 1)));
                  final t0 = ref.read(telemetryProvider);
                  await cloud.report(t0.current, token: auth.token);
                  messenger.showSnackBar(SnackBar(
                    content: Text(cloud.lastError == null
                        ? '测试上报成功，请刷新看板'
                        : '测试上报失败：${cloud.lastError}'),
                  ));
                },
                child: const Text('测试上报'),
              ),
            );
          }),
          Consumer(builder: (context, wref, _) {
            final auth = wref.watch(authProvider);
            return SwitchListTile(
              secondary:
                  const Icon(Icons.science_outlined, color: Color(0xFF27D6E6)),
              title: const Text('演示数据同步到看板',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                auth.isLoggedIn
                    ? '演示模式登录后自动同步，看板标注为"演示"（仅自己可见）；可在此关闭'
                    : '登录后自动把演示数据同步到你的看板（仅自己可见）',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              value: t.demoReport,
              activeThumbColor: const Color(0xFF27D6E6),
              onChanged: (v) {
                if (v && !auth.isLoggedIn) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AuthScreen()));
                  return;
                }
                t.setDemoReport(v);
              },
            );
          }),
          ListTile(
            leading: const Icon(Icons.system_update, color: Color(0xFF27D6E6)),
            title: const Text('检查更新', style: TextStyle(color: Colors.white)),
            subtitle: const Text('从服务器获取最新版并下载安装',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            onTap: () => _checkUpdate(),
          ),
          ListTile(
            leading: const Icon(Icons.science, color: Color(0xFFFF6B3D)),
            title: const Text('扩展实验室（游戏UDP/手柄/圈速/CSV/Trigger）',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('v2.15 新功能统一入口',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const LabScreen())),
          ),
          _header('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF27D6E6)),
            title:
                const Text('REV 车机仪表盘', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'v2.16.0 · 行程轨迹回放 / 驾驶评分 · 连接向导 · 报警语音 · 保养提醒 · 故障码维修建议 · 云端趋势 · 更多 PID',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          ListTile(
            leading:
                const Icon(Icons.bug_report_outlined, color: Color(0xFF27D6E6)),
            title:
                const Text('运行日志（闪退排查）', style: TextStyle(color: Colors.white)),
            subtitle: const Text('若出现闪退，可在此查看异常记录并截图反馈',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right,
                color: Colors.white24, size: 20),
            onTap: () => _showCrashLog(),
          ),
        ],
      ),
    );
  }

  Future<void> _showCrashLog() async {
    final logs = await CrashGuard.readLogs();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E141B),
        title: Row(
          children: [
            const Expanded(
                child: Text('运行日志',
                    style: TextStyle(color: Colors.white, fontSize: 18))),
            TextButton(
              onPressed: () async {
                await CrashGuard.clearLogs();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child:
                  const Text('清空', style: TextStyle(color: Color(0xFF27D6E6))),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: logs.isEmpty
              ? const Text('没有异常记录，运行正常。',
                  style: TextStyle(color: Colors.white54, fontSize: 13))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in logs)
                      Container(
                        width: double.maxFinite,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        color: Colors.white.withOpacity(0.05),
                        child: Text(e,
                            style: const TextStyle(
                                color: Color(0xFFFFB4A8),
                                fontSize: 10,
                                fontFamily: 'monospace',
                                height: 1.35)),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭', style: TextStyle(color: Color(0xFF27D6E6))),
          ),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white38,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      );

  String _qualityLabel(AudioQuality q) => switch (q) {
        AudioQuality.high => '高（强制 hi 高清）',
        AudioQuality.low => '低（强制 lo 压缩）',
        AudioQuality.auto => '自动（手机 hi / 车机 lo）',
      };

  Future<void> _pickAudioQuality(BuildContext context) async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF11161D),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in const [
            ('auto', '自动（手机 hi / 车机 lo）'),
            ('high', '高（强制 hi 高清）'),
            ('low', '低（强制 lo 压缩）'),
          ])
            ListTile(
              title: Text(label, style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, v),
            ),
        ]),
      ),
    );
    if (sel == null) return;
    await EngineSoundService.instance.setAudioQuality(sel);
    if (mounted) setState(() {});
  }

  Future<void> _editEndpoint(CloudService cloud) async {
    final ctrl = TextEditingController(text: cloud.endpoint);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11161D),
        title: const Text('云服务器地址', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'http://你的服务器:8080/api/v1/report',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            const Text('填入后车辆数据每 3 秒上报；留空则不上报。',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () {
                ctrl.text = CloudService.defaultEndpoint;
              },
              child: const Text('恢复默认')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await cloud.setEndpoint(ctrl.text);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败：$e')),
          );
        }
        return;
      }
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存云服务器地址')),
        );
      }
    }
  }

  Future<void> _checkUpdate() async {
    final cloud = ref.read(cloudServiceProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在检查更新…'), duration: Duration(seconds: 1)),
    );
    const currentCode = AppEnvironment.versionCode;
    Map<String, dynamic>? rel;
    try {
      rel = await cloud.checkUpdate(currentCode);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$e')),
      );
      return;
    }
    if (!mounted) return;
    if (rel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本')),
      );
      return;
    }
    final name = rel['versionName'] ?? '';
    final notes = rel['notes'] ?? '';
    final apkUrl = rel['apkUrl'] ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11161D),
        title:
            Text('发现新版本 v$name', style: const TextStyle(color: Colors.white)),
        content: Text(notes.isEmpty ? '是否立即下载并安装？' : notes,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Android 8+ 需要"安装未知应用"权限；未授权先申请并引导。
              final granted = await cloud.ensureInstallPermission();
              if (!mounted) return;
              if (!granted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('未授权安装：请到系统设置允许本应用安装应用后重试'),
                    duration: Duration(seconds: 4),
                  ),
                );
                await openAppSettings();
                return;
              }
              try {
                await cloud.downloadAndInstall(apkUrl, onProgress: (p) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('下载中 $p%'),
                          duration: const Duration(milliseconds: 600)),
                    );
                  }
                });
              } catch (e) {
                if (!mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (mctx) => AlertDialog(
                    backgroundColor: const Color(0xFF11161D),
                    title: const Text('自动安装失败',
                        style: TextStyle(color: Colors.white)),
                    content: Text(
                      '下载或调起安装失败：$e\n\n可手动安装：\n'
                      '1) 浏览器打开：\n$apkUrl\n'
                      '2) 或到 Download 目录找 rev-update.apk 点击安装。',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.5),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(mctx),
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  String _skinDesc(String id) {
    switch (id) {
      case 'metro':
        return '玻璃磁贴 · 青色数据流';
      case 'nerv':
        return '赤色诊断 · 六边形面板';
      case 'touge':
        return '水墨山路 · JDM 笔触';
      case 'nervr':
        return '赛道换挡灯 · 青橙温度条 · 高密度';
      case 'apex':
        return '赛博霓虹 · 品红青双色 · 垂直转速 · 机甲立绘';
      case 'cluster':
        return '赛车橙 · 圆形转速表 · 大车速 · 数据流';
      case 'cyanhex':
        return '青眼六边形 · 垂直转速条 · 点阵档位';
      case 'supercar':
        return '超跑 · 水平RPM条 · 巨型车速 · 六小表';
      case 'ambergt':
        return '金瞳琥珀 · J形转速条 · 点阵档位 · GT徽章';
      case 'amberNerv':
        return '琥珀诊断 · 暖橙NERV · 渐变转速条 · 无头盔立绘';
      default:
        return '';
    }
  }
}
