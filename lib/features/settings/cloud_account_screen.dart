import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/auth/auth_screen.dart';
import 'package:obd_dashboard/features/privacy/privacy_screen.dart';
import 'package:obd_dashboard/features/settings/settings_common.dart';
import 'package:obd_dashboard/services/cloud_service.dart';

/// 账号与云端：登录、服务器地址、上报状态、演示同步、隐私开关。
class CloudAccountScreen extends ConsumerStatefulWidget {
  const CloudAccountScreen({super.key});

  @override
  ConsumerState<CloudAccountScreen> createState() => _CloudAccountScreenState();
}

class _CloudAccountScreenState extends ConsumerState<CloudAccountScreen> {
  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '账号与云端',
      body: ListView(
        children: [
          const SettingsHeader('账号'),
          _accountTile(),
          const SettingsHeader('云服务器'),
          _endpointTile(),
          _plaintextWarning(),
          _reportStatusTile(),
          _demoReportTile(),
          const SettingsHeader('隐私与数据'),
          Consumer(builder: (context, wref, _) {
            final cloud = wref.watch(cloudServiceProvider);
            return SettingsTile(
              icon: Icons.shield_outlined,
              title: '隐私与数据说明',
              subtitle:
                  '${cloud.cloudUpload ? '上传车辆数据' : '仅本地使用（不上传）'}'
                  ' · ${cloud.gpsUpload ? '包含位置' : '不含位置'}'
                  ' · 可随时查看/修改',
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PrivacyScreen(gate: false)));
                if (mounted) setState(() {});
              },
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _accountTile() {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      return SettingsTile(
        icon: Icons.account_circle_outlined,
        color: const Color(0xFFFF6B3D),
        title: '未登录',
        subtitle: '登录或注册后，车辆数据才会上报到你的专属看板',
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AuthScreen()));
          if (mounted) setState(() {});
        },
      );
    }
    final isAdmin = auth.isAdmin;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B3D).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isAdmin ? Icons.admin_panel_settings : Icons.account_circle,
          color: const Color(0xFFFF6B3D),
          size: 21,
        ),
      ),
      title: Text(auth.username ?? '',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(
          isAdmin ? '管理员 · 可查看全部车辆' : '普通用户 · 仅查看自己的车辆',
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: TextButton(
        onPressed: _confirmLogout,
        child: const Text('退出登录'),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final auth = ref.read(authProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11161D),
        title: const Text('退出登录？', style: TextStyle(color: Colors.white)),
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
    if (ok != true) return;
    try {
      await auth.logout();
    } catch (_) {
      // 本地状态已清除即可，忽略网络异常
    }
    if (mounted) setState(() {});
  }

  Widget _endpointTile() {
    final cloud = ref.watch(cloudServiceProvider);
    return SettingsTile(
      icon: Icons.cloud_outlined,
      title: '云服务器地址',
      subtitle: cloud.needsUserServer
          ? '未配置：请填写你自己部署的服务器地址（留空则不上报、不检查更新）'
          : (cloud.endpointHealed
              ? '${cloud.endpoint}\n已自动修正地址（原先多写了路径）'
              : cloud.endpoint),
      trailing: const Icon(Icons.edit, color: Colors.white24, size: 18),
      onTap: () => _editEndpoint(cloud),
    );
  }

  Widget _plaintextWarning() {
    final cloud = ref.watch(cloudServiceProvider);
    if (!cloud.isPlaintextPublic) return const SizedBox.shrink();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: const Icon(Icons.gpp_maybe, color: Color(0xFFFF6B3D)),
      title: const Text('当前使用明文 HTTP 直连 IP',
          style: TextStyle(color: Color(0xFFFFB4A8), fontSize: 13)),
      subtitle: const Text('数据在网络上是未加密的。建议给服务器配置域名 + HTTPS 证书后改用域名地址。',
          style: TextStyle(color: Colors.white38, fontSize: 11)),
      dense: true,
    );
  }

  Widget _reportStatusTile() {
    final cloud = ref.watch(cloudServiceProvider);
    final auth = ref.watch(authProvider);
    ref.watch(telemetryProvider); // 随遥测刷新，状态实时可见
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(
        err != null || !auth.isLoggedIn ? Icons.cloud_off : Icons.cloud_done,
        color: err != null || !auth.isLoggedIn
            ? const Color(0xFFFF6B3D)
            : kSettingsAccent,
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
              content: Text('正在测试上报…'), duration: Duration(seconds: 1)));
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
  }

  Widget _demoReportTile() {
    final auth = ref.watch(authProvider);
    final t = ref.watch(telemetryProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.science_outlined, color: kSettingsAccent),
      title: const Text('演示数据同步到看板', style: TextStyle(color: Colors.white)),
      subtitle: Text(
        auth.isLoggedIn
            ? '演示模式登录后自动同步，看板标注为"演示"（仅自己可见）；可在此关闭'
            : '登录后自动把演示数据同步到你的看板（仅自己可见）',
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      value: t.demoReport,
      activeThumbColor: kSettingsAccent,
      onChanged: (v) {
        if (v && !auth.isLoggedIn) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AuthScreen()));
          return;
        }
        t.setDemoReport(v);
      },
    );
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
            onPressed: () => ctrl.text = CloudService.defaultEndpoint,
            child: const Text('恢复默认'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
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
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存云服务器地址')),
    );
  }
}
