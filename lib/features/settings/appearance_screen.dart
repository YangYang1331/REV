import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/skin/skin_registry.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/vehicle/engine_pack_mapping.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/settings/engine_pack_screen.dart';
import 'package:obd_dashboard/features/settings/settings_common.dart';
import 'package:obd_dashboard/services/engine_sound_service.dart';
import 'package:obd_dashboard/services/screen_awake.dart';
import 'package:obd_dashboard/services/sound_service.dart';

/// 外观与显示：皮肤、开屏动效、常亮、声浪与音效。
class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  final ScreenAwake _awake = ScreenAwake();

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final t = ref.watch(telemetryProvider);
    return SettingsScaffold(
      title: '外观与显示',
      body: ListView(
        children: [
          const SettingsHeader('仪表盘皮肤'),
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
          const SettingsHeader('屏幕与动画'),
          SwitchListTile(
            title: const Text('危险红屏告警', style: TextStyle(color: Colors.white)),
            subtitle: const Text('水温过高 / 转速越红区时全屏闪烁',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            value: t.redFlash,
            activeColor: kSettingsAccent,
            onChanged: (v) => t.setRedFlash(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome, color: kSettingsAccent),
            title: const Text('地平线动效', style: TextStyle(color: Colors.white)),
            subtitle: const Text('开屏多表自检扫表 / 青色背光 / 警示灯逐亮 / 进仪表盘一次性光扫',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: AppStore.horizonFx,
            activeColor: kSettingsAccent,
            onChanged: (v) {
              AppStore.instance.setHorizonFx(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bolt, color: kSettingsAccent),
            title: const Text('开屏动画', style: TextStyle(color: Colors.white)),
            subtitle: const Text('默认开：通电仪表自检扫针 → REV 定版自绘序列；关闭则直接进入仪表盘',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: AppStore.videoSplash,
            activeColor: kSettingsAccent,
            onChanged: (v) {
              AppStore.instance.setVideoSplash(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('保持屏幕常亮', style: TextStyle(color: Colors.white)),
            value: _awake.enabled,
            activeColor: kSettingsAccent,
            onChanged: (v) => _awake.setEnabled(v),
          ),
          const SettingsHeader('声音与触感'),
          SwitchListTile(
            secondary: const Icon(Icons.vibration, color: kSettingsAccent),
            title: const Text('音效与触感反馈', style: TextStyle(color: Colors.white)),
            subtitle: const Text('连接成功提示音 / 告警震动提示',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: SoundService.instance.enabled,
            activeColor: kSettingsAccent,
            onChanged: (v) {
              SoundService.instance.setEnabled(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.surround_sound, color: Color(0xFFFF6B3D)),
            title: const Text('模拟声浪（随转速）',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('排气脉冲音高只随转速变化，负荷与挡位只改音色；进仪表盘才发声，默认关闭',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: EngineSoundService.instance.enabled,
            activeColor: kSettingsAccent,
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

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
