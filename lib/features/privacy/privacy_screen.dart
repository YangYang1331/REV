import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/dashboard/dashboard_screen.dart';

/// 隐私与数据授权。
///
/// 两种用法：
///  - [gate] = true：首次启动/政策升版时拦截，必须明确同意后才能进仪表盘；
///  - [gate] = false：设置里的"隐私与数据"，随时查看与撤回。
///
/// 位置属于敏感个人信息，默认关闭，必须单独勾选；关闭后 App 连定位都不申请，
/// 而不是"申请了但不上传"。
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key, this.gate = false});

  final bool gate;

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _agreed = false;
  bool _cloud = true;
  bool _gps = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = AppStore.instance;
    final cloud = await store.getCloudUpload();
    final gps = await store.getGpsUpload();
    if (!mounted) return;
    setState(() {
      _cloud = cloud;
      _gps = gps;
      _loading = false;
    });
  }

  Future<void> _apply({required bool cloud, required bool gps}) async {
    final c = ref.read(cloudServiceProvider);
    await c.setCloudUpload(cloud);
    // 不上传车辆数据时，位置自然也不上传，避免开关状态自相矛盾。
    await c.setGpsUpload(cloud && gps);
  }

  Future<void> _finish({required bool consent}) async {
    if (consent) {
      await AppStore.instance.setPrivacyConsent(AppStore.privacyVersion);
    }
    await _apply(cloud: _cloud, gps: _gps);
    if (!mounted) return;
    if (widget.gate) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B10),
      appBar: widget.gate
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              title: const Text('隐私与数据'),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                    20, widget.gate ? 28 : 8, 20, 28),
                children: [
                  if (widget.gate) ...[
                    const Text('REV',
                        style: TextStyle(
                            color: Color(0xFF27D6E6),
                            fontSize: 13,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('隐私与数据说明',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('开始前请花一分钟读完，你的数据由你自己决定去哪。',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 18),
                  ],
                  _block('我们处理哪些数据', [
                    '车辆 OBD 数据：转速、车速、水温、油温、电压、节气门、故障码等，'
                        '只来自你自己插的 ELM327 适配器。',
                    '设备标识：首次启动生成的随机串（rev-xxxx），用于区分车辆，'
                        '不含手机号、IMEI 或通讯录。',
                    '账号：用户名与密码散列，用于看板鉴权。',
                    '位置：仅当你在这里打开"上传位置"后，才会随数据帧上传经纬度；'
                        '默认关闭，关闭时 App 不申请定位权限。',
                  ]),
                  _block('用来做什么', [
                    '在你自己的服务器上显示实时看板与历史曲线。',
                    '断网时把数据帧暂存在手机本地，联网后补传（最多约 1 小时）。',
                    '排查连接与数据异常。不用于广告，不出售，不做用户画像。',
                  ]),
                  _block('存在哪里、存多久', [
                    '上报地址由你在"设置 → 云服务器地址"里指定，默认指向你自己的域名。',
                    '服务器上超过 48 小时没有新数据的设备会被自动清理；'
                        '登录令牌失效即删。',
                    '手机本地离线队列随卸载一起消失，也可在设置里清除。',
                  ]),
                  _block('你的权利', [
                    '随时关闭"上传车辆数据"（仅本地使用）或"上传位置"，立即生效。',
                    '要求导出或删除服务器上的数据：联系服务器管理员（通常就是你自己）。',
                    '撤回同意：在"设置 → 隐私与数据"里关闭即可。',
                  ]),
                  _block('权限说明', [
                    '蓝牙：连接 BLE ELM327 适配器；定位：仅用于可选的轨迹上传。',
                    '前台服务/开机自启：车机熄屏或重启后仍保持仪表与声浪运行。',
                  ]),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF27D6E6),
                    value: _cloud,
                    onChanged: (v) => setState(() => _cloud = v),
                    title: const Text('上传车辆数据到我的看板',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text('关闭后仅本机使用，不发送任何数据',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF27D6E6),
                    value: _gps,
                    onChanged: _cloud ? (v) => setState(() => _gps = v) : null,
                    title: const Text('同时上传位置（可选）',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text('位置属于敏感个人信息，默认关闭；关闭时看板只显示车辆数据',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                  if (widget.gate) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF27D6E6),
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      title: const Text('我已阅读并同意上述说明',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text('不同意也可以仅本地使用，功能不受影响（除云端看板）',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _agreed ? () => _finish(consent: true) : null,
                      child: const Text('同意并继续'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _cloud = false);
                        _finish(consent: true);
                      },
                      child: const Text('仅本地使用（不上传）'),
                    ),
                  ] else ...[
                    if (!_cloud)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('当前为"仅本地使用"：不会向任何服务器发送数据。',
                            style: TextStyle(
                                color: Colors.orange.shade300, fontSize: 12)),
                      ),
                    FilledButton(
                      onPressed: () => _finish(consent: true),
                      child: const Text('保存'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '本应用不提供医疗、法律或维修建议；行车中请勿操作屏幕。',
                    style: TextStyle(
                        color: Colors.white24, fontSize: 11, height: 1.5),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _block(String title, List<String> lines) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Color(0xFF27D6E6),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5)),
            const SizedBox(height: 6),
            ...lines.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('· ',
                          style: TextStyle(color: Colors.white38)),
                      Expanded(
                        child: Text(l,
                            style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                                height: 1.55)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      );
}
