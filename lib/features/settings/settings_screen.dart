import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/skin/skin_registry.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/core/vehicle/engine_pack_mapping.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/auth/auth_screen.dart';
import 'package:obd_dashboard/features/lab/lab_screen.dart';
import 'package:obd_dashboard/features/settings/engine_pack_screen.dart';
import 'package:obd_dashboard/features/settings/speed_calibration_screen.dart';
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
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(_skinDesc(s.id),
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
                            style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  ref.read(telemetryProvider).setProfile(VehicleProfile.byId(v));
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
              style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
            ),
          ),
          _header('校准'),
          ListTile(
            leading: const Icon(Icons.speed, color: Color(0xFF27D6E6)),
            title: const Text('速度校准', style: TextStyle(color: Colors.white)),
            subtitle: Text('当前系数 ${t.speedFactor.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SpeedCalibrationScreen()));
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
            secondary: const Icon(Icons.surround_sound, color: Color(0xFFFF6B3D)),
            title: const Text('模拟声浪（随转速）', style: TextStyle(color: Colors.white)),
            subtitle: const Text('进仪表盘后按实时转速合成引擎轰鸣，默认关闭避免扰民',
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
          _header('账号 · 车队看板'),
          Consumer(builder: (context, wref, _) {
            final auth = wref.watch(authProvider);
            if (!auth.isLoggedIn) {
              return ListTile(
                leading: const Icon(Icons.account_circle_outlined,
                    color: Color(0xFFFF6B3D)),
                title: const Text('未登录',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('登录或注册后，车辆数据才会上报到你的专属看板',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white24),
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
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
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
              leading: const Icon(Icons.cloud_outlined, color: Color(0xFF27D6E6)),
              title: const Text('云服务器地址', style: TextStyle(color: Colors.white)),
              subtitle: Text(cloud.endpoint,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: const Icon(Icons.edit, color: Colors.white24, size: 18),
              onTap: () => _editEndpoint(cloud),
            );
          }),
          Consumer(builder: (context, wref, _) {
            final auth = wref.watch(authProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.science_outlined, color: Color(0xFF27D6E6)),
              title: const Text('演示数据同步到看板', style: TextStyle(color: Colors.white)),
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
            subtitle: const Text('v2.14 新功能统一入口',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LabScreen())),
          ),
          _header('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF27D6E6)),
            title: const Text('REV 车机仪表盘', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'v2.14.0 · band 内连续变调 + 真实采样 22 套 · 采样音质高/低/自动三档 · OBD 自动协议+WiFi+坏帧过滤 · 故障码清除 · 电影感开屏 · 车队看板',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined, color: Color(0xFF27D6E6)),
            title: const Text('运行日志（闪退排查）', style: TextStyle(color: Colors.white)),
            subtitle: const Text('若出现闪退，可在此查看异常记录并截图反馈',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
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
            const Expanded(child: Text('运行日志', style: TextStyle(color: Colors.white, fontSize: 18))),
            TextButton(
              onPressed: () async {
                await CrashGuard.clearLogs();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('清空', style: TextStyle(color: Color(0xFF27D6E6))),
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
                color: Colors.white38, fontWeight: FontWeight.w600, fontSize: 12)),
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

  Future<void> _editEndpoint(cloud) async {
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
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
    const currentCode = 40;
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
        title: Text('发现新版本 v$name', style: const TextStyle(color: Colors.white)),
        content: Text(notes.isEmpty ? '是否立即下载并安装？' : notes,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
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
                      SnackBar(content: Text('下载中 $p%'), duration: const Duration(milliseconds: 600)),
                    );
                  }
                });
              } catch (e) {
                if (!mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (mctx) => AlertDialog(
                    backgroundColor: const Color(0xFF11161D),
                    title: const Text('自动安装失败', style: TextStyle(color: Colors.white)),
                    content: Text(
                      '下载或调起安装失败：$e\n\n可手动安装：\n'
                      '1) 浏览器打开：\n$apkUrl\n'
                      '2) 或到 Download 目录找 rev-update.apk 点击安装。',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
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
