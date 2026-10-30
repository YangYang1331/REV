import 'package:flutter/material.dart';

import 'package:obd_dashboard/core/store/app_store.dart';

/// 连接引导 / 预热门（短板6）：连接前的图文检查清单，确认后不再提示。
class PreheatScreen extends StatefulWidget {
  const PreheatScreen({super.key});

  @override
  State<PreheatScreen> createState() => _PreheatScreenState();
}

class _PreheatScreenState extends State<PreheatScreen> {
  bool _ack = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await AppStore.instance.getPreheatAck();
    if (!mounted) return;
    setState(() {
      _ack = v;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String, String)>[
      (Icons.pan_tool, '车辆停稳', '拉手刹、挂 P 挡，确保车辆静止后再插拔 OBD 接口'),
      (Icons.vpn_key, '钥匙转到 ON / ACC', '全车通电但不要点火启动，给 ECU 留出自检时间'),
      (Icons.power_settings_new, '确认 ELM327 上电', '插在方向盘下方 OBD 接口，模块指示灯应亮起'),
      (Icons.hourglass_bottom, '等待 2–3 秒', '让蓝牙模块完成上电自检，再回到连接页搜索'),
      (Icons.local_fire_department, '冷车预热', '冷启动首驶建议低速约 30 秒再激烈驾驶，保护发动机'),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('连接引导 · 预热'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '首次连接前请按清单确认，避免"扫描不到 / 连不上"',
                  style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 12),
                ...items.map((e) => Card(
                      color: const Color(0xFF111823),
                      child: ListTile(
                        leading: Icon(e.$1, color: const Color(0xFFFF6B3D)),
                        title: Text(e.$2,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(e.$3,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12, height: 1.4)),
                      ),
                    )),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _loaded ? _ack : false,
                  activeColor: const Color(0xFFFF6B3D),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('我已了解，不再提示',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  onChanged: (v) {
                    setState(() => _ack = v ?? false);
                    AppStore.instance.setPreheatAck(v ?? false);
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B3D),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.bluetooth_connected, size: 18),
                  label: const Text('去连接'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
