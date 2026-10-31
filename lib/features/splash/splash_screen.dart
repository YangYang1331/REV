import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/features/dashboard/dashboard_screen.dart';
import 'package:obd_dashboard/features/dashboard/widgets/horizon_fx.dart';
import 'package:obd_dashboard/features/privacy/privacy_screen.dart';
import 'package:obd_dashboard/services/sound_service.dart';

/// 开屏导航策略【纯逻辑决策】——不碰任何动画时钟/原生播放器，便于单测：
///  - 开屏动画开关关 → 立即进主页（不播任何动画，直接淡入 DashboardScreen）；
///  - 开关开 → 播纯 Flutter 自绘电影感序列；动画正常播完即进主页；
///  - 任何卡住（动画控制器停滞/回调未触发）→ [SplashNavPolicy.absoluteMaxHold]
///    绝对硬上限兜底强制进主页，绝不白屏/卡死。
class SplashNavPolicy {
  SplashNavPolicy({required this.animationEnabled});

  /// 开屏动画是否播放（prefs key 沿用 rev_video_splash，默认 true）。
  final bool animationEnabled;

  /// 计划动画时长（4.0s）：正常播完即进主页。
  static const Duration plannedDuration = Duration(milliseconds: 4000);

  /// 全程绝对硬上限（9s）：任何卡住/未完成都强制进主页。
  static const Duration absoluteMaxHold = Duration(milliseconds: 9000);

  bool get shouldPlayAnimation => animationEnabled;

  /// 给定已流逝时间与"动画是否已正常完成"，决定是否进主页。
  bool shouldGoHome({
    required Duration elapsed,
    required bool animationCompleted,
  }) {
    if (!animationEnabled) return true; // 开关关：不播动画，立即进
    if (animationCompleted) return true; // 正常播完
    return elapsed >= absoluteMaxHold; // 动画卡住 → 硬上限兜底
  }
}

/// 启动页：REV 真车「点火自检」电影感序列——纯 Flutter CustomPainter 自绘
/// （v2.12.0 恢复 v2.8.0 地平线电影感画面层，不依赖任何 mp4/video_player）。
///
/// 绝对主角是 REV 自身的应用图标（圆角方块大转速表，[ _GaugePainter ] 自绘）与 REV 名称。
/// Forza Horizon 开屏语言：黑底多块仪表自检扫表、cyan/teal 背光逐一点亮、一排描边警示灯
/// 逐亮、DSEG7 LED 读数闪烁、整组仪表随镜头 pan+rotate 扫过、标题橙色光带横扫白字 +
/// 地面镜面倒影 + 速度线冲刺。这些「地平线层」受总开关 [AppStore.horizonFx] 控制：
/// 关闭时回退到原始纯 REV 开屏，但绝不回退 _GaugePainter 主表 / F1 起跑灯 /
/// 指针扫红线回弹 / Orbitron REV 等已有资产。
///
/// 时间轴（单 AnimationController 4.0s，计划完成 4.4s，硬上限 9.0s 必进主界面）：
///  0.00–0.45  上电：黑场，青/白扫描线自上而下，仪表组淡入（暗）。
///  0.35–1.35  自检：F1 起跑灯逐盏；主方表+副圆表指针同扫红线 easeOutBack 回弹；
///             cyan 背光由暗到亮；警示灯逐盏点亮。
///  1.05       点火爆发：白闪前奏 + 镜头微震 + 火花；此时播放 engine_start.wav。
///  0.50–2.80  镜头：整组仪表 pan + 轻微 rotate 扫过（用户最强调「仪表盘整体转动」）。
///  1.10–1.80  DSEG7 LED 读数闪烁点亮。
///  1.50–2.30  Orbitron REV 逐位点亮（白字强红辉光），红线展开。
///  1.95–2.60  橙色光带从左到右横扫白字标题（LinearGradient shader）；
///             地面镜面倒影淡入 + 极淡镜头光斑。
///  2.30–3.30  冲刺：速度线加速。
///  3.55–3.80  全屏白闪，随后 FadeTransition 进 DashboardScreen。
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// 计划动画总时长（正常播完即进主页）。
  static const Duration plannedDuration = SplashNavPolicy.plannedDuration;

  /// 计划完成兜底：动画正常 4.0s 播完，这里垫到 4.4s 强制进主页。
  static const Duration maxHold = Duration(milliseconds: 4400);

  /// 全程绝对硬上限：任何卡住/未完成都强制进主页，绝不白屏/卡死。
  static const Duration absoluteMaxHold = SplashNavPolicy.absoluteMaxHold;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// 全序列唯一主时钟（开关开时 forward；关开关不启动，直接进主页）。
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SplashScreen.plannedDuration,
  );

  /// 后端决策（纯逻辑，可单测）：开关是否播放开屏动画。
  late final SplashNavPolicy _policy =
      SplashNavPolicy(animationEnabled: AppStore.videoSplash);
  bool get _animate => _policy.shouldPlayAnimation;

  /// 地平线电影感层总开关（关闭时回退纯 REV 开屏，主表/扫针/REV 仍在）。
  late final bool _fx = AppStore.horizonFx;

  bool _navigated = false;
  bool _enginePlayed = false;

  Timer? _hardTimer; // 计划完成兜底（4.4s）
  Timer? _absTimer; // 全程 9s 绝对硬上限

  /// 当前秒数（0–4.0）。
  double get s => _c.value * 4.0;

  // —— 各阶段曲线 ——

  /// 点火瞬间镜头抖动（1.05–1.25s）。
  Offset get _shake {
    if (s < 1.05 || s > 1.25) return Offset.zero;
    final env = math.sin(math.pi * (s - 1.05) / 0.20);
    return Offset(math.sin(s * 55) * 4 * env, math.cos(s * 47) * 3 * env);
  }

  /// 主方表指针：0.35–1.15 扫到红线，1.35–2.10 回落；2.1s 后怠速微抖。
  double get _needleP {
    double base;
    if (s < 0.35) {
      base = 0;
    } else if (s < 1.15) {
      base = Curves.easeOutBack.transform((s - 0.35) / 0.80);
    } else if (s < 1.35) {
      base = 1.0;
    } else if (s < 2.10) {
      base = 1.0 - Curves.easeInOut.transform((s - 1.35) / 0.75);
    } else {
      // 点火后进入怠速：指针停在最低刻度并轻微抖动（发动机活着的感觉）。
      final idle = 0.05 + 0.045 * math.sin((s - 2.10) * 10.5);
      return (0.006 * idle.clamp(0.0, 1.0)).clamp(0.0, 0.02);
    }
    return base;
  }

  /// cyan 背光亮度：0.35 起，1.30 到全亮，点火后保持。
  double get _backlight => ((s - 0.35) / 0.95).clamp(0.0, 1.0).toDouble();

  /// 副圆表自检扫表（[delay] 错开一点点，成排扫过）。
  double _sideP(double delay) {
    final t = s - 0.42 - delay;
    if (t < 0) return 0;
    if (t < 0.72) {
      return Curves.easeOutBack.transform((t / 0.72).clamp(0.0, 1.0));
    }
    if (t < 0.95) return 1.0;
    final r = ((t - 0.95) / 0.65).clamp(0.0, 1.0);
    return (1.0 - Curves.easeInOut.transform(r)).clamp(0.0, 1.0);
  }

  /// 镜头扫过：0.50–2.80，整体平移 + 轻微转动（仅地平线层开启时）。
  double get _camP => _fx
      ? ((s - 0.50) / 2.30).clamp(0.0, 1.0).toDouble()
      : 0.0;
  Offset get _camPan {
    if (!_fx) return Offset.zero;
    final p = Curves.easeInOut.transform(_camP);
    return Offset(26 * p - 12, 10 * p - 4);
  }

  double get _camRot => _fx ? 0.045 * math.sin(math.pi * _camP) : 0.0; // ≈2.6° 扫过

  /// 镜头推拉：开场 1.28 → 1.00 的推近转拉远，收尾再轻推 1.05（蓄势进主页）。
  double get _camZoom {
    final intro = (1 -
            Curves.easeOutCubic
                .transform(((s - 0.12) / 1.15).clamp(0.0, 1.0)))
        .clamp(0.0, 1.0)
        .toDouble();
    final outro = Curves.easeInOut
        .transform(((s - 2.90) / 0.55).clamp(0.0, 1.0))
        .clamp(0.0, 1.0)
        .toDouble();
    return 1.0 + 0.30 * intro + 0.055 * outro;
  }

  /// 透视镜头矩阵：平移 + 绕 X/Y/Z 轻转 + 推拉，做出 3D 扫过感。
  /// 平移放在最外层，保证抖动/位移仍按屏幕坐标走。
  Matrix4 get _camMatrix {
    final p = Curves.easeInOut.transform(_camP);
    final ry = _fx ? 0.105 * math.sin(math.pi * p) : 0.0; // ≈6°
    final rx = _fx ? -0.032 * math.sin(math.pi * p) : 0.0;
    return Matrix4.identity()
      ..setEntry(3, 2, 0.0014)
      ..translate(_camPan.dx, _camPan.dy)
      ..rotateX(rx)
      ..rotateY(ry)
      ..rotateZ(_camRot)
      ..scale(_camZoom);
  }

  double get _speedIntensity {
    if (s < 0.35) return 0;
    if (s < 1.05) return 0.5 * ((s - 0.35) / 0.70);
    if (s < 1.35) return 0.5 + 0.5 * ((s - 1.05) / 0.30);
    if (s < 2.10) return 1.0 - 0.6 * ((s - 1.35) / 0.75);
    if (s < 3.30) return 0.4 + 0.5 * ((s - 2.10) / 1.20);
    return 0.9;
  }

  double get _flash {
    if (s < 3.55) return 0;
    if (s < 3.68) return (s - 3.55) / 0.13 * 0.8;
    if (s < 3.80) return 0.8 * (1 - (s - 3.68) / 0.12);
    return 0;
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _c.addStatusListener(_onStatus);
    // 全程绝对硬上限：任何卡住/未完成都强制进主界面。
    _absTimer = Timer(SplashScreen.absoluteMaxHold, _goHome);
    // 点火音效服务初始化（点火爆发时播一次；受全局音效开关约束）。
    try {
      unawaited(SoundService.instance.init());
    } catch (_) {}

    if (!_animate) {
      // 开屏动画开关关闭：不播动画，首帧后直接进主页。
      WidgetsBinding.instance.addPostFrameCallback((_) => _goHome());
      return;
    }
    // 动画正常 4.0s 播完即导航；这里垫到 4.4s 做"停滞兜底"。
    _hardTimer = Timer(SplashScreen.maxHold, _goHome);
    try {
      unawaited(_c.forward());
    } catch (e) {
      debugPrint('splash animation failed, fallback to dashboard: $e');
      _goHome();
    }
  }

  void _onStatus(AnimationStatus st) {
    if (st == AnimationStatus.completed) _goHome();
  }

  /// 点火瞬间（指针到红线）播放起动机→点火轰鸣；受全局音效开关控制。
  void _maybePlayEngine() {
    if (_enginePlayed || s < 1.05) return;
    _enginePlayed = true;
    try {
      unawaited(SoundService.instance.playEngineStart());
    } catch (_) {}
  }

  Future<void> _goHome() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    _absTimer?.cancel();
    _hardTimer?.cancel();
    try {
      _c.stop();
    } catch (_) {}
    // 首次启动（或隐私条款版本更新）先过隐私授权页：数据去向/退出方式必须明示并主动同意。
    var accepted = false;
    try {
      accepted = await AppStore.instance.getPrivacyAccepted();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, a, __) => FadeTransition(
          opacity: a,
          child:
              accepted ? const DashboardScreen() : const PrivacyScreen(gate: true),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _absTimer?.cancel();
    _hardTimer?.cancel();
    try {
      _c.removeStatusListener(_onStatus);
      _c.dispose();
    } catch (_) {}
    super.dispose();
  }

  // —— 布局 ——

  double get _logoScale {
    final p = ((s - 0.25) / 0.55).clamp(0.0, 1.0).toDouble();
    if (p <= 0) return 0.82;
    return 0.82 + 0.18 * Curves.easeOutBack.transform(p);
  }

  double get _logoGlow {
    final base = ((s - 0.4) / 0.5).clamp(0.0, 1.0).toDouble() * 0.55;
    var pulse = 0.0;
    if (s >= 1.0 && s <= 1.6) {
      pulse = 0.45 * math.sin(math.pi * (s - 1.0) / 0.6);
    }
    return (base + pulse).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    // 开关关闭：纯黑场（下一帧即进主页，不构建任何动画层）。
    if (!_animate) {
      return const Scaffold(
        backgroundColor: Color(0xFF05080C),
        body: SizedBox.expand(),
      );
    }
    _maybePlayEngine();
    return Scaffold(
      backgroundColor: const Color(0xFF05080C),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Transform.translate(
            offset: _shake,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 透视网格地面（Tron 感）：镜头拉开时从地平线扑面而来。
                Positioned.fill(
                    child: CustomPaint(painter: _GridFloorPainter(s, _fx))),
                Positioned.fill(
                    child: CustomPaint(painter: _CenterGlowPainter(s))),
                // 点火冲击波：两圈从表心扩散。
                Positioned.fill(
                    child: CustomPaint(painter: _ShockwavePainter(s))),
                Positioned.fill(child: CustomPaint(painter: _HudScanPainter(s))),
                Positioned.fill(
                    child: CustomPaint(
                        painter: _SpeedLinesPainter(s, _speedIntensity))),
                Positioned.fill(child: CustomPaint(painter: _SparksPainter(s))),
                Positioned.fill(child: CustomPaint(painter: _StreakPainter(s))),
                // 整组仪表 + 标题：3D 透视镜头（平移 + 绕 Z/Y 轻转 + 推拉）。
                Center(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: _camMatrix,
                    child: _clusterContent(),
                  ),
                ),
                // HUD 四角框 + 准星：开场收拢、结尾再夹紧，收尾进主页。
                Positioned.fill(
                    child: IgnorePointer(
                        child: CustomPaint(painter: _HudFramePainter(s))),
                ),
                if (_flash > 0.01)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.white.withOpacity(_flash),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _clusterContent() {
    final mq = MediaQuery.of(context);
    final short = math.min(mq.size.width, mq.size.height);
    final tachSize = (short * 0.32).clamp(150.0, 240.0).toDouble();
    final sideSize = (short * 0.18).clamp(86.0, 132.0).toDouble();
    final revSize = (short * 0.17).clamp(96.0, 132.0).toDouble();
    final lightsGone = ((s - 1.10) / 0.20).clamp(0.0, 1.0).toDouble();

    final children = <Widget>[
      SizedBox(height: 34, child: Center(child: _startLights(lightsGone))),
      SizedBox(height: short * 0.02),
      // 仪表组：副圆表 + 主方表 + 副圆表（地平线多表自检扫针）
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_fx) ...[
            _roundGauge(sideSize, _sideP(0.0), 'km/h', const Color(0xFF27D6E6)),
            SizedBox(width: short * 0.02),
          ],
          Transform.scale(
            scale: _logoScale,
            child: Container(
              width: tachSize,
              height: tachSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tachSize * 0.22),
                boxShadow: _logoGlow > 0.02
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFF2D2D)
                              .withOpacity(0.55 * _logoGlow),
                          blurRadius: 60 * _logoGlow,
                          spreadRadius: 4 * _logoGlow,
                        ),
                        BoxShadow(
                          color: const Color(0xFF27D6E6)
                              .withOpacity(0.20 * _logoGlow),
                          blurRadius: 90 * _logoGlow,
                        ),
                      ]
                    : null,
              ),
              child: CustomPaint(
                  painter: _GaugePainter(p: _needleP, backlight: _backlight)),
            ),
          ),
          if (_fx) ...[
            SizedBox(width: short * 0.02),
            _roundGauge(sideSize, _sideP(0.07), 'TEMP', const Color(0xFF1DE2D6)),
            SizedBox(width: short * 0.015),
            _roundGauge(sideSize * 0.82, _sideP(0.14), 'FUEL',
                const Color(0xFF7FF0E6)),
          ],
        ],
      ),
      SizedBox(height: short * 0.018),
      if (_fx) _warningRow(),
      if (_fx) SizedBox(height: short * 0.012),
      if (_fx) _ledReadout(),
      SizedBox(height: short * 0.02),
      _revTitleWithReflection(revSize),
      const SizedBox(height: 8),
      _redline(revSize),
      const SizedBox(height: 8),
      _subtitle(),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _roundGauge(double size, double p, String label, Color accent) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: RoundGaugePainter(
          p: p,
          backlight: _backlight,
          label: label,
          accent: accent,
        ),
      ),
    );
  }

  /// 一排描边警示灯：安全带/ABS/机油/电瓶/故障/驻车P/远光，逐盏点亮。
  Widget _warningRow() {
    const icons = HorizonWarning.values;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CustomPaint(
                painter: _WarnLightPainter(
                  type: icons[i],
                  on: _warnOn(i),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _warnOn(int i) {
    final start = 0.95 + i * 0.09;
    final lit = ((s - start) / 0.18).clamp(0.0, 1.0).toDouble();
    // 2.6s 后整体淡出（自检结束）
    final fade = s > 2.6 ? (1 - (s - 2.6) / 0.5).clamp(0.0, 1.0) : 1.0;
    return lit * fade;
  }

  /// DSEG7 LED 读数：自检时闪烁点亮。
  Widget _ledReadout() {
    // 1.1–1.8s 闪烁，之后常亮
    double a;
    if (s < 1.1) {
      a = 0;
    } else if (s < 1.8) {
      a = (math.sin((s - 1.1) * math.pi * 6) > 0) ? 1.0 : 0.15;
    } else {
      a = 1.0;
    }
    final t = ((s - 1.1) / 0.7).clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: t,
      child: Text(
        '0888',
        style: TextStyle(
          fontFamily: 'DSEG7',
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF27D6E6).withOpacity(a),
          shadows: [
            Shadow(
                color: const Color(0xFF27D6E6).withOpacity(0.7 * a),
                blurRadius: 8),
          ],
        ),
      ),
    );
  }

  /// F1 起跑灯。
  Widget _startLights(double gone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++) _lightCell(i, gone),
      ],
    );
  }

  Widget _lightCell(int i, double gone) {
    final lit = ((s - (0.35 + i * 0.11)) / 0.05).clamp(0.0, 1.0).toDouble();
    final base = Color.lerp(
      const Color(0xFFFF3B30),
      const Color(0xFFFF8A30),
      lit * 0.35,
    )!;
    return Opacity(
      opacity: (1 - gone).clamp(0.0, 1.0).toDouble(),
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Color.lerp(const Color(0xFF2A1416), base, lit),
          border: Border.all(color: const Color(0x33FFFFFF)),
          boxShadow: lit > 0
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF4A30).withOpacity(0.8 * lit),
                    blurRadius: 12 * lit,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  /// REV 标题 + 地面镜面倒影（地平线语言）：倒影为翻转副本，淡入后渐隐。
  Widget _revTitleWithReflection(double size) {
    final reflect = ((s - 2.0) / 0.6).clamp(0.0, 1.0).toDouble();
    final title = _revTitle(size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        ClipRect(
          child: Align(
            heightFactor: 0.32,
            child: Opacity(
              opacity: 0.16 * reflect,
              child: Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.identity()..scale(1.0, -1.0),
                child: title,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _revTitle(double size) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++) _revLetter('REV'[i], i, size),
          ],
        ),
        // 橙色光带从左到右横扫白色粗体字
        if (_fx && s > 1.95 && s < 2.60)
          Positioned.fill(
            child: ClipRect(
              child: CustomPaint(
                  painter: _TitleBandPainter(
                      ((s - 1.95) / 0.65).clamp(0.0, 1.0).toDouble())),
            ),
          ),
      ],
    );
  }

  Widget _redline(double size) {
    final p = Curves.easeOut
        .transform(((s - 1.65) / 0.35).clamp(0.0, 1.0).toDouble());
    return SizedBox(
      width: size * 2.55,
      height: 8,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: p,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFFF2D2D),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF2D2D).withOpacity(0.85),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _revLetter(String ch, int i, double size) {
    final lit = ((s - (1.50 + i * 0.18)) / 0.25).clamp(0.0, 1.0).toDouble();
    return Text(
      ch,
      style: TextStyle(
        fontFamily: 'Orbitron',
        fontWeight: FontWeight.w900,
        fontVariations: const [FontVariation('wght', 900)],
        fontSize: size,
        height: 1.0,
        letterSpacing: 8,
        color: Color.lerp(const Color(0xFF1B2027), Colors.white, lit),
        shadows: lit > 0
            ? [
                Shadow(
                  color: const Color(0xFFFF2D2D).withOpacity(0.9 * lit),
                  blurRadius: 18 * lit,
                ),
                Shadow(
                  color: const Color(0xFFFF2D2D).withOpacity(0.45 * lit),
                  blurRadius: 44 * lit,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _subtitle() {
    const full = 'OBD REAL-TIME CLUSTER';
    final t = ((s - 1.9) / 0.9).clamp(0.0, 1.0).toDouble();
    final n = (full.length * Curves.easeOut.transform(t)).floor();
    final typing = n < full.length;
    final cursorOn = (s * 5).floor().isEven;
    final ready = ((s - 2.55) / 0.35).clamp(0.0, 1.0).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: t,
          child: Text(
            '${full.substring(0, n)}${typing && cursorOn ? '▌' : ''}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 2 + 8 * t,
            ),
          ),
        ),
        if (ready > 0.01)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Opacity(
              opacity: ready,
              child: Text(
                'SYSTEM READY // 26 ENGINE SAMPLES',
                style: TextStyle(
                  color: const Color(0xFF27D6E6).withOpacity(0.85 * ready),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 单盏警示灯：委托给共享的 [paintWarningIcon]。
class _WarnLightPainter extends CustomPainter {
  _WarnLightPainter({required this.type, required this.on});
  final HorizonWarning type;
  final double on;
  @override
  void paint(Canvas canvas, Size size) {
    paintWarningIcon(
        canvas, type, Offset.zero & size, horizonWarningColor(type), on);
  }

  @override
  bool shouldRepaint(_WarnLightPainter old) => old.on != on;
}

/// 标题橙色横扫光带：一道窄的橙色/暖白光带从左到右掠过 REV 白字。
class _TitleBandPainter extends CustomPainter {
  _TitleBandPainter(this.p);
  final double p; // 0..1
  @override
  void paint(Canvas canvas, Size size) {
    final x = -size.width * 0.2 + p * size.width * 1.4;
    final rect = Rect.fromLTWH(x - size.width * 0.08, 0,
        size.width * 0.16, size.height);
    final shader = const LinearGradient(
      colors: [
        Colors.transparent,
        Color(0xFFFFB347),
        Color(0xFFFFE9C0),
        Color(0xFFFFB347),
        Colors.transparent,
      ],
      stops: [0.0, 0.35, 0.5, 0.65, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_TitleBandPainter old) => old.p != p;
}

/// 中心点火辉光。
class _CenterGlowPainter extends CustomPainter {
  _CenterGlowPainter(this.s);
  final double s;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) return;
    final vignette = RadialGradient(
      center: Alignment.center,
      radius: 0.92,
      colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
      stops: const [0.55, 1.0],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = vignette);

    final base = ((s - 0.35) / 0.6).clamp(0.0, 1.0).toDouble();
    var pulse = 0.0;
    if (s >= 1.0 && s <= 1.6) {
      pulse = math.sin(math.pi * (s - 1.0) / 0.6);
    }
    final alpha = (0.16 * base + 0.30 * pulse).clamp(0.0, 0.6).toDouble();
    if (alpha <= 0.01) return;
    final c = Offset(size.width * 0.5, size.height * 0.42);
    final r = size.shortestSide * 0.72;
    final glow = RadialGradient(
      colors: [
        const Color(0xFFFF2D2D).withOpacity(alpha),
        const Color(0xFFFF2D2D).withOpacity(alpha * 0.35),
        Colors.transparent,
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawRect(Offset.zero & size, Paint()..shader = glow);
  }

  @override
  bool shouldRepaint(_CenterGlowPainter old) => old.s != s;
}

/// 上电扫描线。
class _HudScanPainter extends CustomPainter {
  _HudScanPainter(this.s);
  final double s;
  @override
  void paint(Canvas canvas, Size size) {
    if (s <= 0.4) {
      final y = (s / 0.4) * size.height;
      final a = (1 - s / 0.4).clamp(0.0, 1.0).toDouble();
      final glow = Paint()
        ..color = const Color(0xFF27D6E6).withOpacity(a * 0.9)
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), glow);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withOpacity(a)
          ..strokeWidth = 1,
      );
    }
    if (s > 0.05 && s < 0.25) {
      final a = (1 - (s - 0.05) / 0.2) * 0.08;
      final p = Paint()
        ..color = Colors.white.withOpacity(a)
        ..strokeWidth = 0.5;
      for (double x = 0; x < size.width; x += 64) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      }
      for (double y = 0; y < size.height; y += 64) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    }
  }

  @override
  bool shouldRepaint(_HudScanPainter old) => old.s != s;
}

/// 径向速度线。
class _SpeedLinesPainter extends CustomPainter {
  _SpeedLinesPainter(this.s, this.intensity);
  final double s;
  final double intensity;

  static final _rnd = math.Random(7);
  static final List<double> _angles =
      List.generate(28, (_) => _rnd.nextDouble() * 2 * math.pi);
  static final List<double> _speeds =
      List.generate(28, (i) => 0.25 + (i % 3) * 0.22);
  static final List<double> _phases =
      List.generate(28, (_) => _rnd.nextDouble());
  static final List<int> _layers = List.generate(28, (i) => i % 3);
  static const List<Color> _palette = [
    Colors.white,
    Color(0xFFFF3B30),
    Color(0xFF27D6E6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01 || size.shortestSide <= 0) return;
    final c = Offset(size.width * 0.5, size.height * 0.42);
    final maxR = size.shortestSide * 0.9;
    for (var i = 0; i < _angles.length; i++) {
      final a = _angles[i];
      final drift = (_phases[i] + s * _speeds[i] * 0.55) % 1.0;
      final r0 = drift * maxR * 0.55;
      final len = (0.10 + 0.22 * drift) * maxR;
      final d = Offset(math.cos(a), math.sin(a));
      final alpha = intensity * (0.25 + 0.65 * drift);
      canvas.drawLine(
        c + d * r0,
        c + d * (r0 + len),
        Paint()
          ..color = _palette[_layers[i]].withOpacity(alpha)
          ..strokeWidth = _layers[i] == 1 ? 2.0 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeedLinesPainter old) =>
      old.s != s || old.intensity != intensity;
}

/// 点火火花。
class _SparksPainter extends CustomPainter {
  _SparksPainter(this.s);
  final double s;
  static final _rnd = math.Random(11);
  static const int _n = 22;
  static final List<double> _ang =
      List.generate(_n, (_) => _rnd.nextDouble() * 2 * math.pi);
  static final List<double> _spd =
      List.generate(_n, (_) => 0.35 + _rnd.nextDouble() * 0.65);

  @override
  void paint(Canvas canvas, Size size) {
    if (s < 1.05 || s > 2.0 || size.shortestSide <= 0) return;
    final t = (s - 1.05) / 0.95;
    final c = Offset(size.width * 0.5, size.height * 0.42);
    final maxR = size.shortestSide * 0.55;
    final p = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _n; i++) {
      final d = Offset(math.cos(_ang[i]), math.sin(_ang[i]));
      final r = t * _spd[i] * maxR;
      final a = (1 - t) * 0.9;
      p
        ..color = (i % 3 == 0 ? Colors.white : const Color(0xFFFF6A30))
            .withOpacity(a)
        ..strokeWidth = 2.0;
      canvas.drawLine(c + d * r, c + d * (r + 10 * (1 - t) + 4), p);
    }
  }

  @override
  bool shouldRepaint(_SparksPainter old) => old.s != s;
}

/// 冲刺水平流光。
class _StreakPainter extends CustomPainter {
  _StreakPainter(this.s);
  final double s;
  @override
  void paint(Canvas canvas, Size size) {
    if (s < 2.3 || s > 3.3) return;
    final p = Curves.easeOut.transform((s - 2.3) / 1.0);
    final x = -size.width * 0.3 + p * size.width * 1.6;
    final y = size.height * 0.685;
    final rect = Rect.fromLTWH(x - 120, y - 1, 240, 2);
    final shader = const LinearGradient(
      colors: [Colors.transparent, Color(0xFFFFE0D0), Colors.transparent],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_StreakPainter old) => old.s != s;
}

/// 开屏主转速表（与 REV 应用图标同形的圆角方块转速表）——完整自绘。
/// [p] 0=怠速左下 → 1=红线尽头右上；[backlight] cyan 背光亮度（0..1）。
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.p, this.backlight = 0});
  final double p;
  final double backlight;

  static const double _startA = 125 * math.pi / 180;
  static const double _spanA = 230 * math.pi / 180;
  static const int _ticks = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    if (W <= 0) return;
    final c = Offset(W / 2, W / 2);
    const endA = _startA + _spanA;
    const redA = _startA + _spanA * 0.82;
    final arcR = W * 0.35;
    final arcRect = Rect.fromCircle(center: c, radius: arcR);

    final radius = Radius.circular(W * 0.22);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    const bg = RadialGradient(
      center: Alignment.center,
      radius: 0.75,
      colors: [Color(0xFF10141B), Color(0xFF020407)],
      stops: [0.4, 1.0],
    );
    canvas.drawRRect(rrect, Paint()..shader = bg.createShader(Offset.zero & size));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = W * 0.005
        ..color = Colors.white.withOpacity(0.14),
    );

    canvas.save();

    // cyan 背光外发光（克制）
    if (backlight > 0.02) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = W * 0.01
          ..color = const Color(0xFF27D6E6).withOpacity(0.35 * backlight)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * backlight),
      );
    }

    // 静态刻度弧：亮白色段 + 红色红区段
    canvas.drawArc(
      arcRect,
      _startA,
      redA - _startA,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = W * 0.020
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withOpacity(0.92)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawArc(
      arcRect,
      redA,
      endA - redA,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = W * 0.030
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF3D2E)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    for (var i = 0; i <= _ticks; i++) {
      final a = _startA + _spanA * i / _ticks;
      final inRed = a >= redA;
      final major = i % 4 == 0;
      final outer = arcR + W * 0.048;
      final inner = arcR + (major ? W * 0.014 : W * 0.028);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + d * inner,
        c + d * outer,
        Paint()
          ..strokeWidth = W * (major ? 0.006 : 0.004)
          ..strokeCap = StrokeCap.round
          ..color = inRed
              ? const Color(0xFFFF5A50)
              : Colors.white.withOpacity(0.85),
      );
    }

    if (p > 0) {
      final sweepEnd = _startA + _spanA * p;
      final whiteEnd = math.min(sweepEnd, redA);
      if (whiteEnd > _startA) {
        canvas.drawArc(
          arcRect,
          _startA,
          whiteEnd - _startA,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = W * 0.022
            ..strokeCap = StrokeCap.round
            ..color = Colors.white
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      if (sweepEnd > redA) {
        canvas.drawArc(
          arcRect,
          redA,
          sweepEnd - redA,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = W * 0.032
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFFF5A40)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }

    final angle = _startA + _spanA * p;
    final len = W * 0.30;
    final hub = W * 0.052;
    final dir = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      c - dir * hub * 0.7,
      c + dir * len,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = W * 0.012
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF4A30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawLine(
      c - dir * hub * 0.5,
      c + dir * len * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = W * 0.004
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFE0D0),
    );

    canvas.restore();

    final hubR = W * 0.052;
    canvas.drawCircle(
      c,
      hubR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFF5A606A), Color(0xFF12151B)],
        ).createShader(Rect.fromCircle(center: c, radius: hubR)),
    );
    canvas.drawCircle(
      c,
      hubR * 0.42,
      Paint()..color = Colors.white.withOpacity(0.28),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.p != p || old.backlight != backlight;
}

/// 透视网格地面（Tron 语言）：射线向地平线汇聚，横向流速线带近大远小
/// 加速滚来。只在地平线层开启时绘制，随开场淡入、冲刺前淡出。
class _GridFloorPainter extends CustomPainter {
  _GridFloorPainter(this.s, this.enabled);
  final double s;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || size.shortestSide <= 0) return;
    final fadeIn = ((s - 0.20) / 0.55).clamp(0.0, 1.0).toDouble();
    final fadeOut =
        s < 2.95 ? 1.0 : (1 - (s - 2.95) / 0.65).clamp(0.0, 1.0).toDouble();
    final a = 0.22 * fadeIn * fadeOut;
    if (a <= 0.01) return;

    final vp = Offset(size.width * 0.5, size.height * 0.44);
    final bottom = size.height;

    // 汇聚射线
    final ray = Paint()
      ..color = const Color(0xFF27D6E6).withOpacity(a * 0.85)
      ..strokeWidth = 1.0;
    for (var i = -9; i <= 9; i++) {
      final x = size.width * 0.5 + i * size.width * 0.115;
      canvas.drawLine(vp, Offset(x, bottom), ray);
    }

    // 横向流速线：t² 做近大远小，随 s 向下滚动
    for (var i = 0; i < 7; i++) {
      final t = ((i / 7) + s * 0.16) % 1.0;
      final y = vp.dy + (bottom - vp.dy) * t * t;
      final half = size.width * (0.03 + 1.05 * t * t);
      canvas.drawLine(
        Offset(size.width * 0.5 - half, y),
        Offset(size.width * 0.5 + half, y),
        Paint()
          ..color = const Color(0xFF27D6E6)
              .withOpacity((0.25 + 0.75 * t) * a)
          ..strokeWidth = 0.6 + 1.6 * t,
      );
    }

    // 地平线辉光带
    final horizon = Rect.fromCenter(
        center: vp, width: size.width * 0.9, height: size.height * 0.10);
    canvas.drawRect(
      horizon,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Color(0x8827D6E6),
            Colors.transparent,
          ],
        ).createShader(horizon),
    );
  }

  @override
  bool shouldRepaint(_GridFloorPainter old) =>
      old.s != s || old.enabled != enabled;
}

/// 点火冲击波：两圈从表心扩散的青色/白色环，配合白闪与火花。
class _ShockwavePainter extends CustomPainter {
  _ShockwavePainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    if (s < 1.02 || s > 2.05 || size.shortestSide <= 0) return;
    final c = Offset(size.width * 0.5, size.height * 0.42);
    for (var i = 0; i < 2; i++) {
      final t = (s - 1.02 - i * 0.13) / 0.70;
      if (t <= 0 || t >= 1) continue;
      final r = size.shortestSide * (0.12 + 0.62 * Curves.easeOutCubic.transform(t));
      final a = (1 - t) * (0.55 - i * 0.18);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * (1 - t) + 0.6
          ..color = const Color(0xFF7FF0E6).withOpacity(a),
      );
      canvas.drawCircle(
        c,
        r * 0.94,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withOpacity(a * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_ShockwavePainter old) => old.s != s;
}

/// HUD 边框：四角 L 形描边 + 中央准星，开场从外收拢、结尾再夹紧后淡出。
class _HudFramePainter extends CustomPainter {
  _HudFramePainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) return;
    final enter = ((s - 0.10) / 0.45).clamp(0.0, 1.0).toDouble();
    final close = ((s - 2.95) / 0.50).clamp(0.0, 1.0).toDouble();
    final out = s > 3.50
        ? (1 - (s - 3.50) / 0.28).clamp(0.0, 1.0).toDouble()
        : 1.0;
    final a = 0.30 * enter * out;
    if (a <= 0.01) return;

    final e = Curves.easeOutCubic.transform(enter);
    final c2 = Curves.easeInOut.transform(close);
    final inset = size.shortestSide * 0.035 + (1 - e) * 30 - c2 * 6;
    final len = size.shortestSide * 0.06;
    final p = Paint()
      ..color = const Color(0xFF27D6E6).withOpacity(a)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    void corner(Offset o, double sx, double sy) {
      canvas.drawLine(o, o + Offset(len * sx, 0), p);
      canvas.drawLine(o, o + Offset(0, len * sy), p);
    }

    corner(Offset(inset, inset), 1, 1);
    corner(Offset(size.width - inset, inset), -1, 1);
    corner(Offset(inset, size.height - inset), 1, -1);
    corner(Offset(size.width - inset, size.height - inset), -1, -1);

    final mid = size.width * 0.5;
    final tick = size.shortestSide * 0.018;
    canvas.drawLine(Offset(mid, inset), Offset(mid, inset + tick), p);
    canvas.drawLine(
        Offset(mid, size.height - inset), Offset(mid, size.height - inset - tick), p);
    canvas.drawLine(Offset(inset, size.height * 0.5),
        Offset(inset + tick * 0.7, size.height * 0.5), p);
    canvas.drawLine(Offset(size.width - inset, size.height * 0.5),
        Offset(size.width - inset - tick * 0.7, size.height * 0.5), p);
  }

  @override
  bool shouldRepaint(_HudFramePainter old) => old.s != s;
}

