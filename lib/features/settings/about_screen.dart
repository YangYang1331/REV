import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:obd_dashboard/core/config/environment.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/lab/lab_screen.dart';
import 'package:obd_dashboard/features/settings/settings_common.dart';
import 'package:obd_dashboard/services/crash_guard.dart';

/// 关于与更新：版本信息、检查更新、扩展实验室、运行日志。
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '关于与更新',
      body: ListView(
        children: [
          const SettingsHeader('版本'),
          const ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Icon(Icons.info_outline, color: kSettingsAccent),
            title: Text('REV 车机仪表盘',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
                'v${AppEnvironment.version} · 行程轨迹回放 / 驾驶评分 · 连接向导 · 报警语音 · 保养提醒 · 故障码维修建议 · 云端趋势 · 更多 PID',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          SettingsTile(
            icon: Icons.system_update,
            title: '检查更新',
            subtitle: '从服务器获取最新版并下载安装',
            onTap: _checkUpdate,
          ),
          const SettingsHeader('工具'),
          SettingsTile(
            icon: Icons.science,
            color: const Color(0xFFFF6B3D),
            title: '扩展实验室',
            subtitle: '游戏 UDP / 手柄 / 圈速 / CSV / Trigger',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const LabScreen())),
          ),
          SettingsTile(
            icon: Icons.bug_report_outlined,
            title: '运行日志（闪退排查）',
            subtitle: '若出现闪退，可在此查看异常记录并截图反馈',
            onTap: _showCrashLog,
          ),
          const SizedBox(height: 24),
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
                  const Text('清空', style: TextStyle(color: kSettingsAccent)),
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
                        color: Colors.white.withValues(alpha: 0.05),
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
            child: const Text('关闭', style: TextStyle(color: kSettingsAccent)),
          ),
        ],
      ),
    );
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
}
