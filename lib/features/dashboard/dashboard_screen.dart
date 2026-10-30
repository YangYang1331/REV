import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/core/skin/skin_registry.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/features/connection/connection_screen.dart';
import 'package:obd_dashboard/features/dashboard/skins/apex_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/amber_gt_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/amber_nerv_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/cluster_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/cyan_hex_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/metro_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/nerv_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/nerv_r_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/supercar_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/dashboard_pages.dart';
import 'package:obd_dashboard/features/dashboard/skins/touge_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/widgets/danger_overlay.dart';
import 'package:obd_dashboard/features/dashboard/widgets/data_mode_selector.dart';
import 'package:obd_dashboard/features/dashboard/widgets/demo_seal.dart';
import 'package:obd_dashboard/features/dashboard/widgets/alert_flash.dart';
import 'package:obd_dashboard/features/dashboard/widgets/alarm_banner.dart';
import 'package:obd_dashboard/features/alarm/alarm_settings_screen.dart';
import 'package:obd_dashboard/features/dashboard/tiles/tiles_board_screen.dart';
import 'package:obd_dashboard/features/maintenance/maintenance_screen.dart';
import 'package:obd_dashboard/features/diagnostic/data_stream_screen.dart';
import 'package:obd_dashboard/features/health/health_report_screen.dart';
import 'package:obd_dashboard/features/debug/debug_ball.dart';
import 'package:obd_dashboard/models/obd_data.dart';
import 'package:obd_dashboard/services/engine_sound_service.dart';
import 'package:obd_dashboard/services/auto_connect.dart';
import 'package:obd_dashboard/services/sound_service.dart';
import 'package:obd_dashboard/features/diagnostic/diagnostic_screen.dart';
import 'package:obd_dashboard/features/health/battery_health_screen.dart';
import 'package:obd_dashboard/features/perf/perf_screen.dart';
import 'package:obd_dashboard/features/settings/settings_screen.dart';
import 'package:obd_dashboard/features/track/lap_screen.dart';
import 'package:obd_dashboard/features/trips/trips_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  bool _chrome = true;
  bool _hud = false;

  // 仪表盘内多页面滑动
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const _pageNames = ['仪表', '经济', '数据'];

  void _toggleHud() {
    HapticFeedback.selectionClick();
    setState(() => _hud = !_hud);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 进仪表盘才启动模拟声浪（开屏只播点火音）；开关默认关，未开则空转。
    final t = ref.read(telemetryProvider);
    // ignore: discarded_futures
    EngineSoundService.instance.onEnterDashboard(
      idleRpm: t.profile.idleRpm.toDouble(),
      redlineRpm: t.profile.redlineRpm.toDouble(),
    );
    // 冷启动（含开机自启）直接停在仪表盘：按上次设备自动连一次，
    // 免得每次上车还要手动进连接页。失败静默，不打扰演示模式。
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  void _autoConnect() {
    final obd = ref.read(obdServiceProvider);
    final tele = ref.read(telemetryProvider);
    AutoConnect.tryKnown(obd: obd, tele: tele);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 回到前台（导航切走、熄屏、车机休眠唤醒）时补一次重连。
    if (state == AppLifecycleState.resumed) _autoConnect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // ignore: discarded_futures
    EngineSoundService.instance.onExitDashboard();
    _pageController.dispose();
    super.dispose();
  }

  bool get _danger {
    final t = ref.read(telemetryProvider);
    final d = t.current;
    if (!t.redFlash) return false;
    final c = d.coolant;
    if (c != null && c >= t.profile.coolantDanger) return true;
    if (d.rpm >= t.profile.rpmDanger) return true;
    return false;
  }

  String get _dangerReason {
    final t = ref.read(telemetryProvider);
    final d = t.current;
    if (d.coolant != null && d.coolant! >= t.profile.coolantDanger) {
      return '!! COOLANT OVERHEAT';
    }
    return '!! RPM OVERREV';
  }

  void _cycleSkin() {
    final cur = ref.read(skinProvider);
    final i = SkinRegistry.all.indexOf(cur);
    final next = SkinRegistry.all[(i + 1) % SkinRegistry.all.length];
    ref.read(skinProvider.notifier).select(next.id);
  }

  Future<void> _openMenu() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0F14),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    _menuTile(Icons.tune, '数据源模式', '演示 DEMO / 实车 OBD · 演示同步',
                        () => const _DataModeRoute()),
                    _menuTile(Icons.speed, '性能测试', '零百 / 零四 / 刹车',
                        () => const PerfScreen()),
                    _menuTile(Icons.flag, '圈速计时', '赛道圈速 / 最佳记录',
                        () => const LapScreen()),
                    _menuTile(Icons.route, '行程记录', '里程 / 油耗历史 / 轨迹回放',
                        () => const TripsScreen()),
                    _menuTile(Icons.build_circle_outlined, '保养提醒',
                        '机油 / 轮胎 / 年检倒计时',
                        () => const MaintenanceScreen()),
                    _menuTile(Icons.notifications_active_outlined, '报警与语音',
                        '阈值 / 语音播报 / 报警记录',
                        () => const AlarmSettingsScreen()),
                    _menuTile(Icons.build, '诊断 / 故障码', '实时数据流 / DTC',
                        () => const DiagnosticScreen()),
                    _menuTile(Icons.battery_charging_full, '电池健康', '启动压降 / 充电检测',
                        () => const BatteryHealthScreen()),
                    _menuTile(Icons.favorite_outline, '健康报告', '电池 / 温度 / 故障码评分',
                        () => const HealthReportScreen()),
                    _menuTile(Icons.dashboard_customize_outlined, '磁贴看板', '长按拖拽 · 自定义指标',
                        () => const TilesBoardScreen()),
                    _menuTile(Icons.list_alt, '实时数据流', '全 PID 逐帧刷新',
                        () => const DataStreamScreen()),
                    _menuTile(Icons.bluetooth, '连接车辆', '演示模式 / BLE',
                        () => const ConnectionScreen()),
                    _menuTile(Icons.palette, '皮肤与设置', '皮肤 / 车型 / 校准',
                        () => const SettingsScreen()),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuTile(
      IconData icon, String title, String sub, Widget Function() page) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF27D6E6)),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => page()));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final t = ref.watch(telemetryProvider);
    final d = t.current;
    final profile = t.profile;

    return Scaffold(
      backgroundColor: skin.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _chrome = !_chrome),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 仪表盘内容（HUD 镜像包整个 PageView）
            _hud
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..scale(-1.0, 1.0),
                    child: _pageView(skin, d, profile),
                  )
                : _pageView(skin, d, profile),
            // 危险告警（全屏红屏）
            DangerOverlay(
                active: _danger, reason: _dangerReason, skin: skin),
            // 超限数值边角闪烁（与全屏红屏互补）
            const AlertFlash(),
            // 报警横幅（水温/油温/电压/超速，6 秒自动收起）
            const Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: AlarmBanner(),
            ),
            // 演示模式明显封条
            if (t.isOffline) const DemoSeal(),
            // 调试悬浮球（仅 debug 构建，release 不渲染）
            if (kDebugMode) const DebugBall(),
            // 顶部状态
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_chrome,
                  child: _TopChrome(
                    demo: t.isOffline,
                    gpsMode: t.isGpsMode,
                    skin: skin,
                    onMenu: _openMenu,
                    onCycleSkin: _cycleSkin,
                    onToggleHud: _toggleHud,
                    hudActive: _hud,
                  ),
                ),
              ),
            ),
            // 底部页面指示器
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_chrome,
                  child: _PageIndicator(
                    currentPage: _currentPage,
                    pageNames: _pageNames,
                    skin: skin,
                    onTap: (i) {
                      _pageController.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 仪表盘内 PageView：皮肤 / 经济 / 数据。
  Widget _pageView(
      SkinDescriptor skin, ObdData d, VehicleProfile profile) {
    return PageView(
      controller: _pageController,
      onPageChanged: (i) => setState(() => _currentPage = i),
      children: [
        // 第一页：当前皮肤（切换皮肤时淡入淡出）
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: KeyedSubtree(
            key: ValueKey<String>(skin.id),
            child: _renderSkin(skin, d, profile),
          ),
        ),
        // 第二页：经济驾驶
        EconomyPage(data: d, profile: profile, skin: skin),
        // 第三页：关键数据
        DataGlancePage(data: d, profile: profile, skin: skin),
      ],
    );
  }

  Widget _renderSkin(SkinDescriptor skin, ObdData d, VehicleProfile profile) {
    return switch (skin.layout) {
      SkinLayout.nerv =>
        NervDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.touge =>
        TougeDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.metro =>
        MetroDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.nervr =>
        NervRDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.apex =>
        ApexDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.cluster =>
        ClusterDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.cyanHex =>
        CyanHexDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.supercar =>
        SupercarDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.amberGt =>
        AmberGtDashboard(data: d, profile: profile, skin: skin),
      SkinLayout.amberNerv =>
        AmberNervDashboard(data: d, profile: profile, skin: skin),
    };
  }

}

/// 顶部状态条：来源徽标 + 时钟 + 皮肤快切 + 菜单。
class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.demo,
    required this.gpsMode,
    required this.skin,
    required this.onMenu,
    required this.onCycleSkin,
    required this.onToggleHud,
    required this.hudActive,
  });
  final bool demo;
  final bool gpsMode;
  final SkinDescriptor skin;
  final VoidCallback onMenu;
  final VoidCallback onCycleSkin;
  final VoidCallback onToggleHud;
  final bool hudActive;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.55), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _btn(Icons.menu, onMenu),
            const SizedBox(width: 8),
            Builder(builder: (_) {
              // demo=橙"演示模式"（必要免责，保留）；real=绿"已连接"；
              // gps=用户自定模式、已知是 GPS，不再弹"GPS 估算"提示，留空。
              if (gpsMode) return const SizedBox.shrink();
              const color = Color(0xFFF2B23B);
              const realColor = Color(0xFF2EE68A);
              final c = demo ? color : realColor;
              final label = demo ? '演示模式' : '已连接';
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.withOpacity(0.5)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: c,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              );
            }),
            const Spacer(),
            Text(
              '$hh:$mm',
              style: TextStyle(
                fontFamily: 'DSEG7',
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: skin.ink,
              ),
            ),
            const SizedBox(width: 8),
            _btn(Icons.flip, onToggleHud, active: hudActive),
            const SizedBox(width: 8),
            _btn(Icons.palette, onCycleSkin),
            const SizedBox(width: 8),
            _SoundToggleButton(skin: skin),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: active
              ? skin.accent.withOpacity(0.25)
              : Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(
              color: active
                  ? skin.accent.withOpacity(0.6)
                  : Colors.white.withOpacity(0.12)),
        ),
        child: Icon(icon, size: 18, color: active ? skin.accent : skin.ink),
      ),
    );
  }
}

/// 顶部快捷音效开关：与设置页共用 SoundService 单例（持久化）。
/// SoundService 不是 ChangeNotifier，故用独立 StatefulWidget 本地持有开关态。
class _SoundToggleButton extends StatefulWidget {
  const _SoundToggleButton({required this.skin});
  final SkinDescriptor skin;

  @override
  State<_SoundToggleButton> createState() => _SoundToggleButtonState();
}

class _SoundToggleButtonState extends State<_SoundToggleButton> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    // 进页面时读取单例当前值（设置页/启动 init 已写入）。
    _enabled = SoundService.instance.enabled;
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    final next = !_enabled;
    try {
      await SoundService.instance.setEnabled(next);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _enabled = next);
    _briefFeedback(next);
  }

  void _briefFeedback(bool on) {
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              on ? '音效 已开启' : '音效 已关闭',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            duration: const Duration(milliseconds: 800),
            behavior: SnackBarBehavior.floating,
            width: 160,
          ),
        );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Tooltip(
      message: _enabled ? '音效 开' : '音效 关',
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _enabled
                ? skin.accent.withOpacity(0.25)
                : Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(
                color: _enabled
                    ? skin.accent.withOpacity(0.6)
                    : Colors.white.withOpacity(0.12)),
          ),
          child: Icon(
            _enabled ? Icons.volume_up : Icons.volume_off,
            size: 18,
            color: _enabled ? skin.accent : skin.ink,
          ),
        ),
      ),
    );
  }
}

/// 数据源模式选择页：演示 DEMO / 实车 OBD + 演示同步开关。
class _DataModeRoute extends ConsumerWidget {
  const _DataModeRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(skinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('数据源模式'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          DataModeSelector(
            onEnterReal: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ConnectionScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: skin.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: skin.panelStroke),
            ),
            child: Text(
              '演示模式：纯本地模拟，不连蓝牙；开启“同步演示数据到看板”后（需登录），看板会以琥珀色演示卡片显示。\n'
              '实车模式：连接 ELM327 后显示真实数据；未连接时不会用演示数据填充，避免误判。\n'
              'GPS 模式：纯手机 GPS 速度，无需 OBD、可离线；转速/档位按车型齿比推算（界面已标注“估算”），水温/电压等 OBD 专有项显示 --。插入 OBD 后自动切回实车模式。',
              style: TextStyle(color: skin.dim, fontSize: 12, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部页面指示器：仪表 / 经济 / 数据，可点击切换。
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.currentPage,
    required this.pageNames,
    required this.skin,
    required this.onTap,
  });

  final int currentPage;
  final List<String> pageNames;
  final SkinDescriptor skin;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageNames.length, (i) {
            final active = i == currentPage;
            return GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: EdgeInsets.symmetric(
                  horizontal: active ? 16 : 12,
                  vertical: 6,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: active
                      ? skin.accent.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active
                        ? skin.accent.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? skin.accent : Colors.white38,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pageNames[i],
                      style: TextStyle(
                        color: active ? skin.accent : Colors.white54,
                        fontSize: 11,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
